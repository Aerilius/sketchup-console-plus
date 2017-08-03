module AE


  class Console


    class Bridge


      class Promise
        # A simple promise implementation to follow the Promise specification for JavaScript (the instance methods):
        # {#link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise }

        # Existing Ruby promise implementations didn't satisfy either in simplicity or similarity to the JavaScript spec.
        # https://github.com/tobiashm/a-ruby-promise/
        # Uses instance eval to provide `return`-keyword-like `resolve` and `reject`, but exposes implementation internals
        # that can have side effects if a same-named instance variable is used in the code block.
        # https://github.com/bachue/ruby-promises/
        # Uses Ruby's `method_missing` to provide a nice proxy functionality to the promise's result. Unfortunately this
        # can cause exceptions when a promise is not yet resolved. Also ruby-like proxies are not realizable in JavaScript.


        # @private
        module State
          PENDING  = 0
          RESOLVED = 1
          REJECTED = 2
        end
        private_constant(:State) if methods.include?(:private_constant)


        # A Struct that stores handlers belonging to a promise.
        # If a promise is resolved or rejected, either the `on_resolve` or `on_reject` code block tells what to do (an
        # action that depended on the promise being fulfilled first).
        # Depending on the success of this handler, resolvation/rejection of the next promise will be invoked by
        # `resolve_next`/`reject_next`.
        # resolved/rejected
        # @private
        Handler = Struct.new(:on_resolve, :on_reject, :resolve_next, :reject_next)
        private_constant(:Handler) if methods.include?(:private_constant)


        # Run an asynchronous operation and return a promise that will receive the result.
        # @overload initialize(executor)
        #   @param [#call(#call(Object),#call(Exception))] executor
        #     A Proc or Method that executes some function and reports back success or failure by calling the parameter
        #     `resolve` with a result or `reject` with the error. The executor must call one of these.
        # @overload initialize {|resolve, reject|}
        #   @yieldparam [#call(*Object)]    resolve  A function to call to fulfill the promise with a result.
        #   @yieldparam [#call(Exception)]  reject   A function to call to reject the promise.
        def initialize(executor=nil, &executor_)
          @state    = State::PENDING
          @value    = nil # result or reason
          @results = []  # all results if multiple were given
          @handlers = []  # @type [Array<Handler>]
          if block_given? || executor.respond_to?(:call)
            executor ||= executor_
            # thread = Thread.new{
            begin
              executor.call(method(:resolve), method(:reject))
            rescue Exception => error
              reject(error)
            end
            # }
            # thread.abort_on_exception = true
          end
        end


        # Register an action to do when the promise is resolved.
        # @overload then(on_resolve, on_reject)
        #   @param [#call(*Object)]           on_resolve  A function to call when the promise is resolved.
        #   @param [#call(String,Exception)]  on_reject   A function to call when the promise is rejected.
        # @overload then {|*results|}
        #   @yield                                        A function to call when the promise is resolved.
        #   @yieldparam [Array<Object>]       results     The promised result (or results).
        # @overload then(on_resolve) {|reason|}
        #   @param      [#call(*Object)]      on_resolve  A function to call when the promise is resolved.
        #   @yield                                        A function to call when the promise is rejected.
        #   @yieldparam [String,Exception]    reason      The reason why the promise was rejected.
        # @return [Promise] A new promise for that the on_resolve or on_reject block has been executed successfully.
        def then(on_resolve=nil, on_reject=nil, &block)
          if block_given?
            if on_resolve.respond_to?(:call)
              # When called as: then(proc{on_resolve}){ on_reject }
              on_reject = block
            else
              # When called as: then{ on_resolve }
              on_resolve = block
            end
          end
          raise ArgumentError("Argument must be callable") unless on_resolve.respond_to?(:call) || on_reject.respond_to?(:call)
          next_promise = self.class.new { |resolve_next, reject_next|
            @handlers << Handler.new(on_resolve, on_reject, resolve_next, reject_next)
          }
          case @state
            when State::RESOLVED
              resolve(*@results)
            when State::REJECTED
              reject(@value)
          end
          return next_promise
        end


        # Register an action to do when the promise is rejected.
        # @param      [#call] on_reject          A function to call when the promise is rejected.
        #                                        (defaults to the given yield block, can be a Proc or Method)
        # @yieldparam [String,Exception] reason  The reason why the promise was rejected
        # @return     [Promise] A new promise that the on_reject block has been executed successfully.
        def catch(on_reject=nil, &block)
          on_reject = block if block_given?
          return self unless on_reject.respond_to?(:call)
          next_promise = self.class.new { |resolve_next, reject_next|
            @handlers << Handler.new(nil, on_reject, resolve_next, reject_next)
          }
          case @state
            when State::REJECTED
              reject(@value)
          end
          return next_promise
        end


        # Resolve a promise once a result has been calculated.
        # @overload resolve(*results)
        #   Resolve a promise once a result or several results have been calculated.
        #   @param [Array<Object>] results
        # @overload resolve(promise)
        #   Resolve a promise with another promise. It will actually be resolved later as soon as the other is resolved.
        #   @param [Promise] promise
        # @return [Promise] This promise
        # @private For convenience. This is supposed to be called from the executor with which the promise is initialized.
        def resolve(*results)
          raise Exception.new("A once rejected promise can not be resolved later") if @state == State::REJECTED
          raise Exception.new("A resolved promise can not be resolved again with different results") if @state == State::RESOLVED && !results.empty? && results != @results
          #return self unless @state == State::PENDING
          if @state == State::PENDING
            # If this promise is resolved with another promise, the final result is not
            # known, so we add a thenable to the second promise to resolve also this one.
            if results.first.respond_to?(:then) # is_a?(self.class)
              promise = results.first
              promise.then(Proc.new { |*results|
                             resolve(*results)
                           }, Proc.new { |reason|
                              reject(reason)
                            })
              return self
            end
            @results = results
            @value   = results.first
            @state   = State::RESOLVED
          end
          until @handlers.empty?
            handler = @handlers.shift
            if handler.on_resolve.respond_to?(:call)
              begin
                new_result = handler.on_resolve.call(*@results)
                if new_result.respond_to?(:then)
                  new_result.then(handler.resolve_next, handler.reject_next)
                elsif handler.resolve_next.respond_to?(:call)
                  handler.resolve_next.call(new_result)
                end
              rescue Exception => error
                AE::Console.error(error)
                if handler.reject_next.respond_to?(:call)
                  handler.reject_next.call(error)
                end
              end
            else # No on_resolve registered.
              if handler.resolve_next.respond_to?(:call)
                handler.resolve_next.call(*@results)
              end
            end
          end
          return self
        end
        alias_method :fulfill, :resolve


        # Reject a promise once it cannot be resolved anymore or an error occured when calculating its result.
        # @param   [String,Exception]  reason
        # @return  [Promise]           This promise
        # @private For convenience. This is supposed to be called from the executor with which the promise is initialized.
        def reject(reason=nil)
          raise Exception.new("A once resolved promise can not be rejected later") if @state == State::RESOLVED
          raise Exception.new("A rejected promise can not be rejected again with different reason") if @state == State::REJECTED && reason != @value
          #return self unless @state == State::PENDING
          if @state == State::PENDING
            @value = reason
            @state = State::REJECTED
          end
          handler_called = false
          until @handlers.empty?
            handler = @handlers.shift
            if handler.on_reject.respond_to?(:call)
              begin
                new_result     = handler.on_reject.call(@value)
                handler_called = true
                if handler.resolve_next.respond_to?(:call)
                  handler.resolve_next.call(new_result)
                end
              rescue Exception => error
                AE::Console.error(error)
                if handler.reject_next.respond_to?(:call)
                  handler.reject_next.call(error)
                end
              end
            else # No on_reject registered.
              if handler.reject_next.respond_to?(:call)
                handler.reject_next.call(@value)
              end
            end
          end
          unless handler_called
            puts "#{self.inspect} rejected with \"#{reason.to_s[0..1000]}\", " + # TODO
                 "but no `on_reject` handler found (#{caller.join("\n")})"
          end
          return self
        end


        # Redefine the inspect method to give shorter output.
        # @override
        # @return [String]
        def inspect
          return "#<#{self.class}:0x#{(self.object_id << 1).to_s(16)}>"
        end


      end # class Promise


    end # class Bridge


  end


end
