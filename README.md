# SdbLock

Poor man's distributed lock using SimpleDB. It is useful when you don't want to
maintain distributed lock server by yourself.

## Installation

Add this line to your application's Gemfile:

    gem 'sdb_lock'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sdb_lock

## Usage

````
require 'sdb_lock'

lock = SdbLock.new(
  'my_app_lock_domain',  # SimpleDB domain name to use
  create_domain: true,   # At the first time, you will need to create domain. Note it might take long time.

  # Other hash members will be passed to AWS::SimpleDB#new as is.
  # You can set credential by other ways including environmental variables.
  # See https://github.com/amazonwebservices/aws-sdk-for-ruby

  # see http://docs.amazonwebservices.com/general/latest/gr/rande.html#sdb_region
  simple_db_endpoint: "sdb.ap-northeast-1.amazonaws.com",
  access_key_id: YOUR_AWS_ACCESS_KEY,
  secret_access_key: YOUR_AWS_SECRET
)

locked = lock.try_lock("a1") do
  # do some work
end

# if you want to block until gain lock, then
lock.lock("a1") do
  # do some work
end

# List locked resource names
lock.locked_resources

# Some times lock might remain because of network failure. Then we'll need
# a way to unlock these.
#
# Unlock older than 10 secs.
lock.unlock_old(10)

````

## Limitation

* Lock might remain by network failure or other reason. See `#unlock_old`.
*

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
