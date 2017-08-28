class AsyncMiniTestHelper

  def initialize(testcase, accept_call_count, timeout=10)
    @testcase = testcase
    @accept_call_count = accept_call_count
    @count = 0
    @timeout = Time.now + timeout
  end

  def done()
    @count += 1
    if @count == @accept_call_count+1 # only the first time the limit is exceeded
      @testcase.assert_equal(@accept_call_count, @count, 'Too many calls to `async.done()`')
      # TODO: This is a failure but it does not increase the failures count, only the assertion count.
    end
  end

  def await()
    while @count < @accept_call_count
      if @timeout < Time.now
        @testcase.assert_equal(@accept_call_count, @count, "Async test timed out. Either some calls to `async.done()` never occur or you should increase the timeout\n#{caller.first}")
        return nil
      end
      sleep(0.01)
      Thread.pass
    end
    @testcase.assert(true, "It should call `async.done()´ #{@accept_call_count} times")
    nil
  end

  def await_timeout()
    while @count < @accept_call_count
      if @timeout < Time.now
        @testcase.assert(true, "It should timeout")
        return nil
      end
      sleep(0.01)
      Thread.pass
    end
    @testcase.assert(false, "It should never call `async.done()´")
    nil
  end

end
