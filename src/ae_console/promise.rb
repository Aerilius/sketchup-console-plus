module AE

  module ConsolePlugin

    class Bridge

      class Promise
        # A simple promise implementation to follow the ES6 (JavaScript) Promise specification:
        # {#link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise }
        #
        # Existing Ruby promise implementations did not satisfy either in simplicity or compliance to the ES6 spec.
        #
        # https://github.com/tobiashm/a-ruby-promise/
        #     Uses instance eval to provide `return`-keyword-like `resolve` and `reject`, but exposes implementation
        #     internals that can have side effects if a same-named instance variable is used in the code block.
        #
        # https://github.com/bachue/ruby-promises/
        #     Uses Ruby's `method_missing` to provide a nice proxy to the promise's result. Unfortunately this can cause
        #     exceptions when a promise is not yet resolved. Also ruby-like proxies can not be realised in JavaScript.

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
        # @param executor     [#call(#call(Object),#call(Exception))]
        #   An executor receives a callable to resolve the promise with a result and
        #   a callable to reject the promise in case of an error. The executor must call one of both.
        # @yieldparam resolve [#call(*Object)]   A function to call to fulfill the promise with a result.
        # @yieldparam reject  [#call(Exception)] A function to call to reject the promise.
        def initialize(&executor)
          @state    = State::PENDING
          @values   = []  # all results or rejection reasons if multiple were given
          @handlers = []  # @type [Array<Handler>]
          if block_given? && (executor.arity == 2 || executor.arity < 0)
            begin
              executor.call(method(:resolve), method(:reject))
            rescue Exception => error
              reject(error)
            end
          end
        end

        # Register an action to do when the promise is resolved.
        #
        # @overload then(on_resolve, on_reject)
        #   @param on_resolve   [#call(*Object)]          A function to call when the promise is resolved.
        #   @param on_reject    [#call(String,Exception)] A function to call when the promise is rejected.
        #
        # @overload then{|*results|}
        #   @yield                                        A function to call when the promise is resolved.
        #   @yieldparam results [Array<Object>]           The promised result (or results).
        #
        # @overload then(on_resolve){|reason|}
        #   @param on_resolve   [#call(*Object)]          A function to call when the promise is resolved.
        #   @yield                                        A function to call when the promise is rejected.
        #   @yieldparam reason  [String,Exception]        The reason why the promise was rejected.
        #
        # @return [Promise] A new promise for that the on_resolve or on_reject block has been executed successfully.
        def then_do(on_resolve=nil, on_reject=nil, &block)
          if block_given?
            if on_resolve.respond_to?(:call)
              # When called as: then(proc{on_resolve}){ on_reject }
              on_reject = block
            else
              # When called as: then{ on_resolve }
              on_resolve = block
            end
          end
          (unhandled_rejection(*@values); return self) if @state == State::REJECTED && !on_reject.respond_to?(:call)

          next_promise = Promise.new { |resolve_next, reject_next| # Do not use self.class.new because a subclass may require arguments.
            @handlers << Handler.new(on_resolve, on_reject, resolve_next, reject_next)
            case @state
              when State::RESOLVED
                if on_resolve.respond_to?(:call)
                  handle(on_resolve, resolve_next, reject_next)
                end
              when State::REJECTED
                if on_reject.respond_to?(:call)
                  handle(on_reject, resolve_next, reject_next)
                end
            end
          }
          return next_promise
        end

        # Register an action to do when the promise is rejected.
        # @param on_reject   [#call]            A function to call when the promise is rejected.
        #                                       (defaults to the given yield block, can be a Proc or Method)
        # @yieldparam reason [String,Exception] The reason why the promise was rejected
        # @return            [Promise]          A new promise that the on_reject block has been executed successfully.
        def catch(on_reject=nil, &block)
          on_reject = block if block_given?
          return self.then_do(nil, on_reject)
        end

        # Creates a promise that is resolved from the start with the given value.
        # @param  [Array<Object>]  *results  The result with which to initialize the resolved promise.
        # @return [Promise]                  A new promise that is resolved to the given value.
        def self.resolve(*results)
          return self.new{ |on_resolve, on_reject| on_resolve.call(*results) }
        end

        # Creates a promise that is rejected from the start with the given reason.
        # @param  [Array<Object>]  *reasons  The reason with which to initialize the rejected promise.
        # @return [Promise]                  A new promise that is rejected to the given reason.
        def self.reject(*reasons)
          return self.new{ |on_resolve, on_reject| on_reject.call(*reasons) }
        end

        # Creates a promise that resolves as soon as all of a list of promises have been resolved.
        # When all promises are resolved, the new promise is resolved with a list of the individual promises' results.
        # If instead any of the promises is rejected, it rejects the new promise with the first rejection reason.
        # @param  [Array<Promise>] promises  An array of promises.
        # @return [Promise]                  A new promise about the successful completion of all input promises.
        def self.all(promises)
          return Promise.reject(ArgumentError.new('Argument must be iterable')) unless promises.is_a?(Enumerable)
          return Promise.new{ |resolve, reject|
            if promises.empty?
              resolve.call([])
            else
              pending_counter = promises.length
              results = Array.new(promises.length)
              promises.each_with_index{ |promise, i|
                if promise.respond_to?(:then_do)
                  promise.then_do(Proc.new{ |result|
                    results[i] = result
                    pending_counter -= 1
                    resolve.call(results) if pending_counter == 0
                  }, reject) # reject will only run once
                else
                  results[i] = promise # if it is an arbitrary object, not a promise
                  pending_counter -= 1
                  resolve.call(results) if pending_counter == 0
                end
              }
            end
          }
        end

        # Creates a promise that resolves or rejects as soon as the first of a list of promises is resolved or rejected.
        # @param  [Array<Promise>] promises  An array of promises.
        # @return [Promise]                  A new promise about the first completion of the any of the input promises.
        def self.race(promises)
          return Promise.reject(ArgumentError.new('Argument must be iterable')) unless promises.is_a?(Enumerable)
          return Promise.new{ |resolve, reject|
            promises.each{ |promise|
              if promise.respond_to?(:then_do)
                promise.then_do(resolve, reject)
              else
                break resolve.call(promise) # non-Promise value
              end
            }
          }
        end

        private

        # Resolve a promise once a result has been computed.
        #
        # @overload resolve(*results)
        #   Resolve a promise once a result or several results have been computed.
        #   @param *results [Array<Object>]
        #
        # @overload resolve(promise)
        #   Resolve a promise with another promise. It will actually be resolved later as soon as the other is resolved.
        #   @param promise  [Promise]
        #
        # @return           [nil]
        def resolve(*results)
          raise Exception.new("A once rejected promise can not be resolved later") if @state == State::REJECTED
          raise Exception.new("A resolved promise can not be resolved again with different results") if @state == State::RESOLVED && !results.empty? && results != @values
          return nil unless @state == State::PENDING

          # If this promise is resolved with another promise, the final results are not yet
          # known, so we we register this promise to be resolved once all results are resolved.
          raise TypeError.new('A promise cannot be resolved with itself.') if results.include?(self)
          if results.find{ |r| r.respond_to?(:then_do) }
            self.class.all(results).then_do(Proc.new{ |results| resolve(*results) }, method(:reject))
            return nil
          end

          # Update the state.
          @values  = results
          @state   = State::RESOLVED

          # Trigger the queued handlers.
          until @handlers.empty?
            handler = @handlers.shift
            if handler.on_resolve.respond_to?(:call)
              handle(handler.on_resolve, handler.resolve_next, handler.reject_next)
            else
              # No on_resolve handler given: equivalent to identity { |*results| *results }, so we call resolve_next
              # See: https://www.promisejs.org/api/#Promise_prototype_then
              if handler.resolve_next.respond_to?(:call)
                handler.resolve_next.call(*@values)
              end
            end
          end
          # We must return nil, otherwise if this promise is resolved inside the 
          # block of an outer Promise, the block would implicitely return a 
          # resolved Promise and cause complicated errors.
          return nil
        end

        # Reject a promise once it cannot be resolved anymore or an error occured when calculating its result.
        # @param  *reasons [Array<String,Exception,Promise>]
        # @return          [nil]
        def reject(*reasons)
          raise Exception.new("A once resolved promise can not be rejected later") if @state == State::RESOLVED
          raise Exception.new("A rejected promise can not be rejected again with a different reason (#{@values}, #{reasons})") if @state == State::REJECTED && reasons != @values
          return nil unless @state == State::PENDING

          # If this promise is rejected with another promise, the final reasons are not yet
          # known, so we we register this promise to be rejected once all reasons are resolved.
          raise(TypeError, 'A promise cannot be rejected with itself.') if reasons.include?(self)
          # TODO: reject should not do unwrapping according to https://github.com/getify/You-Dont-Know-JS/blob/master/async%20%26%20performance/ch3.md
          #if reasons.find{ |r| r.respond_to?(:then) }
          #  self.class.all(reasons).then(Proc.new{ |reasons| reject(*reasons) }, method(:reject))
          #  return
          #end

          # Update the state.
          @values = reasons
          @state  = State::REJECTED

          # Trigger the queued handlers.
          if @handlers.empty?
            # No "then"/"catch" handlers have been added to the promise.
            unhandled_rejection(*@values)
          else
            # Otherwise: Potentially handlers are awaiting results.
            # If no catch handler is called, the rejection might get unnoticed, so we emit a warning.
            until @handlers.empty?
              handler = @handlers.shift
              if handler.on_reject.respond_to?(:call)
                handle(handler.on_reject, handler.resolve_next, handler.reject_next)
              else
                # No on_reject handler given: equivalent to identity { |reason| raise(reason) }, so we call reject_next
                # See: https://www.promisejs.org/api/#Promise_prototype_then
                if handler.reject_next.respond_to?(:call)
                  handler.reject_next.call(*@values)
                end
              end
            end
          end
          # We must return nil, otherwise if this promise is rejected inside the 
          # block of an outer Promise, the block would implicitely return a 
          # resolved Promise and cause complicated errors.
          return nil
        end

        # Executes a handler and passes on its results or error.
        # @param reaction   [Proc]
        # @param on_success [Proc]
        # @param on_failure [Proc]
        # @note  Precondition: Status is already set to State::RESOLVED or State::REJECTED
        def handle(reaction, on_success, on_failure)
          defer{
            begin
              new_results = *reaction.call(*@values)
              if new_results.find{ |r| r.respond_to?(:then_do) }
                self.class.all(new_results).then_do(Proc.new{ |results| on_success.call(*results) }, on_failure)
              elsif on_success.respond_to?(:call)
                on_success.call(*new_results)
              end
            rescue StandardError => error
              if on_failure.respond_to?(:call)
                on_failure.call(error)
              end
              ConsolePlugin.error(error)
            end
          }
        end

        def unhandled_rejection(*reasons)
          reason = reasons.first
          warn("Uncaught promise rejection with reason [#{reason.class}]: \"#{reason}\"")
          if reason.is_a?(Exception) && reason.backtrace
            # Make use of the backtrace to point at the location of the uncaught rejection.
            filtered_backtrace = reason.backtrace.inject([]){ |lines, line|
              break lines if line.match(__FILE__)
              lines << line
            }
            location = filtered_backtrace.last[/[^\:]+\:\d+/] # /path/filename.rb:linenumber
          else
            filtered_backtrace = caller.inject([]){ |lines, line|
              next lines if line.match(__FILE__)
              lines << line
            }
            location = filtered_backtrace.first[/[^\:]+\:\d+/] # /path/filename.rb:linenumber
          end
          Kernel.warn(filtered_backtrace.join($/))
          Kernel.warn("Tip: Add a Promise#catch block to the promise after the block in #{location}")
        end

        # Redefine the inspect method to give shorter output.
        # @override
        # @return [String]
        def inspect
          return "#<#{self.class}:0x#{(self.object_id << 1).to_s(16)}>"
        end

        def defer(&callback)
          UI.start_timer(0.0, false, &callback)
          return nil
        end

        class Deferred

          def initialize
            @resolve = nil
            @reject = nil
            @promise = Promise.new{ |resolve, reject|
              @resolve = resolve
              @reject = reject
            }
          end
          attr_reader :promise

          def resolve(*results)
            @resolve.call(*results)
          end

          def reject(*reasons)
            @reject.call(*reasons)
          end

        end # class Deferred

      end # class Promise

    end # class Bridge

  end

end
