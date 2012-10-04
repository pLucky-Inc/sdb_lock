require 'minitest/unit'
require 'minitest/autorun'
require "sdb_lock"

class LockTest < MiniTest::Unit::TestCase
  def setup
    @lock = SdbLock.new(
        'lock_test',
        create_domain: true,
        simple_db_endpoint: "sdb.ap-northeast-1.amazonaws.com"
    )
    @lock.unlock("test")
  end

  # This test will take long time (16 secs in my environment).
  def test_try_lock
    shared_var = 0
    locked_count = 0

    threads = 10.times.map do
      Thread.new do
        Thread.pass
        locked = @lock.try_lock("test") { shared_var += 1 }
        locked_count += 1 if locked
      end
    end
    threads.each { |thread| thread.join }
    assert_equal(locked_count, shared_var)
  end

  def test_lock
    shared_var = 0
    threads = 10.times.map do
      Thread.new do
        Thread.pass
        @lock.lock("test") { shared_var += 1 }
      end
    end
    threads.each { |thread| thread.join }
    assert_equal(10, shared_var)
  end
end
