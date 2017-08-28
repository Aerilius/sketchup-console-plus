require_relative 'test_helper'

module AE

  module ConsolePlugin

    require 'ae_console/promise.rb'

    unless defined?(self.error)
      def self.error(*e)
      end
    end

    class TC_Promise < TestCase

      Promise = Bridge::Promise

      # Make Promise#defer synchronous for the test
      class Promise
        def defer(&callback)
          callback.call
          return nil
        end
      end # class Promise

      def setup
      end

      def teardown
      end

      def test_new
      end

      def test_all
        # Resolving all promises
        expected = [1, 2, 3]
        actual = nil
        deferred1 = Promise::Deferred.new
        deferred2 = Promise::Deferred.new
        Promise.all([deferred1.promise, deferred2.promise, 3]).then(Proc.new{ |v|
          actual = v
        }, Proc.new{ |r|
        })
        deferred1.resolve(expected[0])
        assert_equal(nil, actual, "After resolving one of many promises, Promise.all is not yet resolved")
        deferred2.resolve(expected[1])
        assert_equal(expected, actual, "After resolving all promises, Promise.all is resolved")
        # Rejecting one promise
        reason = 'some reason'
        actual = nil
        deferred1 = Promise::Deferred.new
        deferred2 = Promise::Deferred.new
        Promise.all([deferred1.promise, deferred2.promise, 3]).then(Proc.new{ |v|
        }, Proc.new{ |r|
          actual = r
        })
        deferred1.reject(reason)
        assert_equal(reason, actual, "When one promise is rejected, Promise.all is also rejected")
        # Empty array given
        expected = []
        actual_result = nil
        Promise.all([]).then(Proc.new{ |v|
          actual_result = v
        }, Proc.new{ |r|
          actual_reason = v
        })
        assert_equal(expected, actual_result, "When the promises array is empty, Promise.all is immediately resolved")
      end

      def test_race
        # Resolving first promise
        expected = 1
        actual_result = nil
        deferred1 = Promise::Deferred.new
        deferred2 = Promise::Deferred.new
        Promise.race([deferred1.promise, deferred2.promise]).then(Proc.new{ |v|
          actual_result = v
        }, Proc.new{ |r|
        })
        deferred1.resolve(expected)
        assert_equal(expected, actual_result, "After resolving one promise, Promise.race is resolved")
        # Rejecting first promise
        reason = 'some reason'
        actual_reason = nil
        deferred1 = Promise::Deferred.new
        deferred2 = Promise::Deferred.new
        Promise.race([deferred1.promise, deferred2.promise]).then(Proc.new{ |v|
        }, Proc.new{ |r|
          actual_reason = r
        })
        deferred1.reject(reason)
        deferred1.reject('some reason')
        assert_equal(reason, actual_reason, "After rejecting one Promise, Promise.race is also rejected")
        # Non-Promise given
        expected = 2
        actual_result = nil
        deferred1 = Promise::Deferred.new
        deferred2 = Promise::Deferred.new
        Promise.race([deferred1.promise, 2]).then(Proc.new{ |v|
          actual_result = v
        }, Proc.new{ |r|
        })
        assert_equal(expected, actual_result, "When the promises array contains a non-Promise, Promise.race is immediately resolved")
        # Empty array given
        actual_result = nil
        actual_reason = nil
        Promise.race([]).then(Proc.new{ |v|
          actual_result = v
        }, Proc.new{ |r|
          actual_reason = v
        })
        assert_equal(nil, actual_result, "When the promises array is empty, Promise.race is never resolved")
        assert_equal(nil, actual_reason, "When the promises array is empty, Promise.race is never rejected")
      end

      def test_then # Tests also Promise.resolve and Promise.reject
        promise1 = Promise.new
        promise2 = promise1.then{ |_| }
        assert_kind_of(Promise, promise2, "It returns a new promise.")
        assert(promise1 != promise2, "It returns a new promise.")
        # then on a resolved promise
        actual_resolved = false
        resolved = Promise.resolve('some result')
        resolved.then(Proc.new{ |v|
          actual_resolved = true
        }){ |r|
          actual_resolved = false
        }
        assert(actual_resolved, "A thenable on a resolved promise executes immediately the on_resolve callback")
        # then on a rejected promise
        actual_rejected = false
        rejected = Promise.reject('some reason')
        rejected.then(Proc.new{ |v|
          actual_rejected = false
        }, Proc.new{ |r|
          actual_rejected = true
        })
        assert(actual_rejected, "A thenable on a rejected promise executes immediately the on_reject callback")
        # Resolve empty thenable
        actual_resolved = false
        deferred = Promise::Deferred.new
        promise1 = deferred.promise
        promise2 = promise1.then()
        promise3 = promise1.then(Proc.new{ |v|
          actual_resolved = true
        }){ |r|
          actual_resolved = false
        }
        deferred.resolve('some result')
        assert(actual_resolved, "A thenable without callbacks returns a Promise that resolves/rejects subsequent thenables")
        # Reject empty thenable
        actual_rejected = false
        deferred = Promise::Deferred.new
        promise1 = deferred.promise
        promise2 = promise1.then()
        promise3 = promise1.then(Proc.new{ |v|
          actual_rejected = false
        }){ |r|
          actual_rejected = true
        }
        deferred.reject('some reason')
        assert(actual_rejected, "A thenable without callbacks returns a Promise that resolves/rejects subsequent thenables")
      end

      def test_catch
        promise1 = Promise.new
        promise2 = promise1.catch{ |_| }
        assert(promise1 != promise2, "It returns a new promise.")
        # catch on a rejected promise
        actual_rejected = false
        reason = 'some reason'
        rejected = Promise.reject(reason)
        rejected.catch{ |r|
          actual_rejected = true
        }
        assert(actual_rejected, "A thenable on a rejected promise executes immediately the on_reject callback")
      end

      def test_transitions
        value = "value"
        reason = "reason"
        other_value = "other_value"
        other_reason = "other_reason"
        counter1_resolved = 0
        counter1_rejected = 0
        counter2_resolved = 0
        counter2_rejected = 0
        # Create Promise 1
        result1 = nil
        resolved1 = false
        deferred1 = Promise::Deferred.new
        deferred1.promise.then(Proc.new{ |v|
          counter1_resolved += 1
          result1 = v
          resolved1 = true
        }, Proc.new{ |r|
          counter1_rejected += 1
          result1 = r
          resolved1 = false
        })
        # Create Promise 2
        result2 = nil
        rejected2  = false
        deferred2 = Promise::Deferred.new
        deferred2.promise.then(Proc.new{ |v|
          counter2_resolved += 1
          result2 = v
          rejected2 = false
        }, Proc.new{ |r|
          counter2_rejected += 1
          result2 = r
          rejected2 = true
        })
        # Pending, resolve
        deferred1.resolve(value)
        assert(resolved1, "Pending, resolve: It transitions to resolved.")
        assert_equal(result1, value, "Pending, resolve: It has a value.")
        # Pending, reject
        deferred2.reject(reason)
        assert(rejected2, "Pending, reject: It transitions to rejected.")
        assert_equal(result2, reason, "Pending, reject: It has a reason.")
        # Resolved, resolve
        assert_raises(Exception){
          deferred1.resolve(other_value)
        }
        assert(resolved1, "Resolved, resolve: It does not transition to other states.")
        assert_equal(result1, value, "Resolved, resolve: It does not change the result.")
        assert_equal(counter1_resolved, 1, "Resolved: on_resolve is only called once.")
        # Resolved, reject
        assert_raises(Exception){
          deferred1.reject(other_reason)
        }
        assert(resolved1, "Resolved, reject: It does not transition to other states.")
        assert_equal(result1, value, "Resolved, reject: It does not change the result.")
        assert_equal(counter1_rejected, 0, "Resolved: on_reject is not called if on_resolve has been called.")
        # Rejected, resolve
        assert_raises(Exception){
          deferred2.resolve(other_value)
        }
        assert(rejected2, "Rejected, resolve: It does not transition to other states.")
        assert_equal(result2, reason, "Rejected, resolve: It does not change the result.")
        assert_equal(counter2_resolved, 0, "Rejected: on_resolve is not called if on_reject has been called.")
        # Rejected, reject
        assert_raises(Exception){
          deferred2.reject(other_reason)
        }
        assert(rejected2, "Rejected, reject: It does not transition to other states.")
        assert_equal(result2, reason, "Rejected, reject: It does not change the result.")
        assert_equal(counter2_rejected, 1, "Rejected: on_reject is only called once.")
      end

      def test_on_resolve
        value = "value"
        called_with = nil
        deferred = Promise::Deferred.new
        deferred.promise.then(Proc.new{ |v| called_with = v })
        deferred.resolve(value)
        assert_equal(called_with, value, "on_resolve is called with fulfillment value.")
        # Resolving with a promise
        value = "value"
        called_with = nil
        deferred1 = Promise::Deferred.new
        deferred1.promise.then(Proc.new{ |v| called_with = v })
        deferred2 = Promise::Deferred.new
        deferred2.promise.then(Proc.new{ |v| called_with = v })
        deferred1.resolve(deferred2.promise)
        assert_equal(called_with, nil, "When resolved with a promise, on_resolve is not called before the fulfillment promise is resolved.")
        deferred2.resolve(value)
        assert_equal(called_with, value, "When resolved with a promise, on_resolve is not called before the fulfillment promise is resolved.")
      end

      def test_on_reject
        reason = "reason"
        called_with = nil
        deferred = Promise::Deferred.new
        deferred.promise.then(nil, Proc.new{ |r| called_with = r })
        deferred.reject(reason)
        assert_equal(called_with, reason, "on_reject is called with rejection reason.")
        # Rejecting with a promise
        reason = "reason"
        called_with = nil
        deferred1 = Promise::Deferred.new
        deferred1.promise.then(Proc.new{ |v| called_with = v })
        deferred2 = Promise::Deferred.new
        deferred2.promise.then(Proc.new{ |v| called_with = v })
        deferred1.reject(deferred2.promise)
        assert_equal(called_with, nil, "When resolved with a promise, on_reject is not called before the reason promise is resolved.")
        deferred2.resolve(reason)
        assert_equal(called_with, reason, "When rejected with a promise, on_reject is not called before the reason promise is resolved.")
      end

      # Adds two levels to the backtrace before the raise.
      def helper_nested_raise(*args)
        Proc.new{
          raise(*args)
        }.call
      end

      def test_unhandled_rejection
        reason = "The reason is #{rand}"
        out, err = capture_io{
          Promise.new{ |resolve, reject| helper_nested_raise(RuntimeError, reason) }
          .then{|result|}
        }
        assert_match(reason, err, "An uncaught exception in executor prints a warning")

        rejecter = nil
        Promise.new{ |resolve, reject| rejecter = reject }
        .then{|result|}
        out, err = capture_io{
          rejecter.call(reason)
        }
        assert_match(reason, err, "An uncaught rejection prints a warning")

        resolver = nil
        Promise.new{ |resolve, reject| resolver = resolve }
        .then{ |result| result + 1 }
        .then{ |result| helper_nested_raise(RuntimeError, reason) }
        .then{|result|}
        out, err = capture_io{
          resolver.call(42)
        }
        assert_match(reason, err, "An uncaught rejection after then(s) prints a warning")

        resolver1 = nil
        resolver2 = nil
        Promise.new{ |resolve, reject| resolver1 = resolve }
        .then{ |result|
           Promise.new{ |resolve, reject| resolver2 = resolve }
           .then{ |result2| result + result2 }
        }
        .then{ |result| helper_nested_raise(RuntimeError, reason) }
        .then{|result|}.then{|result1|}.then{|result2|}
        out, err = capture_io{
          resolver1.call(3)
          resolver2.call(2)
        }
        assert_match(reason, err, "An uncaught rejection prints a warning")
        assert(err.scan(reason).length == 1, "An uncaught rejection prints exactly one warning")

        resolver1 = nil
        rejecter1 = nil
        Promise.new{ |resolve, reject| resolver1 = resolve }
        .then{ |result|
          Promise.new{ |resolve, reject| rejecter1 = reject }
        }
        .then{|result|}
        out, err = capture_io{
          resolver1.call(3)
          rejecter1.call(reason)
        }
        assert_match(reason, err, "An uncaught rejection prints a warning")
      end

    end # class TC_Promise

  end

end
