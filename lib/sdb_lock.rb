require "sdb_lock/version"

require 'aws'

# Lock using SimpleDB conditional put.
#
# Create instance.
# lock = SdbLock.new('my_app_lock', access_key_id: YOUR_AWS_ACCESS_KEY, secret_access_key: YOUR_AWS_SECRET)
#
# Or if you set up AWS account in another way.
# lock = SdbLock.new('my_app_lock')
#
# Try lock, unlock.
# lock_gained = lock.try_lock("abc")
# lock.unlock("abc") if lock_gained
#
# Try lock with block. It unlocks after block execution is finished.
# executed = lock.try_lock("abc") do
#   # some work
# end
#
# Unlock old ones.
# lock.unlock_old(60)  # Unlock all of older than 60 secs
class SdbLock


  # Attribute name to be used to save locked time
  LOCK_TIME = 'lock_time'

  # Max wait secs for #lock
  MAX_WAIT_SECS = 2

  # Constructor
  #
  # @param [String] domain_name SimpleDB domain name
  # @param [Hash] options
  def initialize(domain_name, options = {})
    @sdb = AWS::SimpleDB.new(options)
    options = options.dup
    if options.has_key?(:create_domain)
      @sdb.domains.create(domain_name) if options[:create_domain]
      options.delete(:create_domain)
    end
    @domain = @sdb.domains[domain_name]
  end

  # Try to lock resource_name
  #
  # @param [String] resource_name name to lock
  # @return [TrueClass] true when locked, unless false
  def try_lock(resource_name)
    attributes = {LOCK_TIME => format_time(Time.now), unless: LOCK_TIME}
    item(resource_name).attributes.set(attributes)
    if block_given?
      begin
        yield
      ensure
        unlock(resource_name)
      end
    end
    true
  rescue AWS::SimpleDB::Errors::ConditionalCheckFailed
    false
  end

  # lock resource_name
  # It blocks until lock is succeeded.
  #
  # @param [String] resource_name
  def lock(resource_name)
    wait_secs = 0.5
    while true
      lock = try_lock(resource_name)
      break if lock
      sleep([wait_secs, MAX_WAIT_SECS].min)
      wait_secs *= 2
    end

    if block_given?
      begin
        yield
      ensure
        unlock(resource_name)
      end
    else
      true
    end
  end

  # Unlock resource_name
  # @param [String] resource_name name to unlock
  def unlock(resource_name, expected_lock_time = nil)
    if expected_lock_time
      item(resource_name).attributes.delete(LOCK_TIME, if: {LOCK_TIME => expected_lock_time})
    else
      item(resource_name).attributes.delete(LOCK_TIME)
    end
    true
  rescue AWS::SimpleDB::Errors::ConditionalCheckFailed
    false
  end

  # Locked time for resource_name
  # @return [Time] locked time, nil if it is not locked
  def locked_time(resource_name)
    attribute = item(resource_name).attributes[LOCK_TIME]
    lock_time_string = attribute.values.first
    Time.at(lock_time_string.to_i) if lock_time_string
  end

  # All locked resources
  #
  # @param [Fixnum] age_in_seconds select resources older than this seconds
  def locked_resources(age_in_seconds = nil)
    if age_in_seconds
      cond = older_than(age_in_seconds)
    else
      cond = "`#{LOCK_TIME}` is not null"
    end
    @domain.items.where(cond).map(&:name)
  end

  # Unlock old resources.
  # It is needed if any program failed to unlock by an unexpected exception
  # or network failure etc.
  #
  # @param [Fixnum] age_in_seconds select resources older than this seconds
  # @return [Array<String>] unlocked resource names
  def unlock_old(age_in_seconds)
    targets = locked_resources(age_in_seconds)
    unlocked = []
    targets.each do |resource_name|
      values = item(resource_name).attributes[LOCK_TIME].values
      next if !values || !values.first || values.first > format_time(Time.now - age_in_seconds)
      succ = unlock(resource_name, values.first)
      unlocked << resource_name if succ
    end
    unlocked
  end

  private

  def item(resource_name)
    @domain.items[resource_name]
  end

  # Format time to compare lexicographically
  def format_time(time)
    # 12 digits is enough until year 9999
    "%012d" % time.to_i
  end

  def older_than(age_in_seconds)
    condition_time = Time.now.utc - age_in_seconds
    "`#{LOCK_TIME}` < '#{format_time(condition_time)}'"
  end
end
