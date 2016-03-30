require "sdb_lock/version"
require 'aws-sdk'

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
    @sdb = ::Aws::SimpleDB::Client.new(options)
    @domain_name = domain_name
    unless domains.include? @domain_name
      @sdb.create_domain(domain_name: @domain_name)
      @domains = @sdb.list_domains.domain_names
    end
  end

  # Try to lock resource_name
  #
  # @param [String] resource_name name to lock
  # @param [Array] additional_attributes include additional attributes
  # @return [TrueClass] true when locked, unless false
  def try_lock(resource_name, additional_attributes = [])
    attributes = [
      {
        name: LOCK_TIME,
        value: format_time(Time.now)
      }
    ].concat(additional_attributes)

    @sdb.put_attributes(
      domain_name: @domain_name,
      item_name: resource_name,
      attributes: attributes,
      expected: {
        name: LOCK_TIME,
        exists: false
      }
    )
    if block_given?
      begin
        yield
      ensure
        unlock(resource_name)
      end
    end
    true
  rescue ::Aws::SimpleDB::Errors::ConditionalCheckFailed
    false
  end

  # lock resource_name
  # It blocks until lock is succeeded.
  #
  # @param [String] resource_name
  # @param [Array] additional_attributes include additional attributes
  def lock(resource_name, additional_attributes = [])
    wait_secs = 0.5
    while true
      lock = try_lock(resource_name, additional_attributes)
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
    expected = if expected_lock_time
      {
        name: LOCK_TIME,
        value: expected_lock_time,
        exists: true
      }
    else
      {}
    end

    @sdb.delete_attributes(
      domain_name: @domain_name,
      item_name: resource_name,
      expected: expected
    )
    true
  rescue ::Aws::SimpleDB::Errors::ConditionalCheckFailed
    false
  end

  # Locked time for resource_name
  # @return [Time] locked time, nil if it is not locked
  def locked_time(resource_name)
    attributes = item(resource_name)
    unless attributes.empty?
      attributes.each do |a|
        break Time.at(a.value.to_i) if a.name == LOCK_TIME
      end
    end
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
    statement = "SELECT * FROM #{@domain_name} WHERE #{cond}"
    @sdb.select(select_expression: statement).items.map { |i| i.name }
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
      value = item(resource_name).each do |attribute|
        break attribute.value if attribute.name == LOCK_TIME
      end
      next if !value || value > format_time(Time.now - age_in_seconds)
      succ = unlock(resource_name, value)
      unlocked << resource_name if succ
    end
    unlocked
  end

  private

  def domains
    @domains ||= @sdb.list_domains.domain_names
  end

  def item(resource_name)
    @sdb.get_attributes(
      domain_name: @domain_name,
      item_name: resource_name
    ).attributes
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
