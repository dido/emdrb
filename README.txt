emdrb
    by Rafael R. Sevilla <dido@imperium.ph>
    http://emdrb.rubyforge.org

== DESCRIPTION:

This is a distributed Ruby client and server which should work as a
drop-in replacement for the standard distributed Ruby implementation
available in the Ruby standard library.

== FEATURES/PROBLEMS:

This is a simple but working DRb client/server implementation that
uses EventMachine as its basis, rather than the default implementation
that uses traditional Ruby sockets.  This should at the very least
play better with other programs that have an EventMachine event loop,
and hopefully provide somewhat better scalability.

Obviously, this is a quick and dirty release, just to get something
out there, and of course it has a number of limitations:

* No SSL support.
* No support for ACLs.
* No support for DRb over Unix domain sockets.
* RSpec tests are very basic, and need a lot more comprehensive work.
* Many standard configuration options for DRb still unsupported

These and many other problems are scheduled to be addressed in the
following releases.

== SYNOPSIS:

EMDRb basically reopens several classes and adds methods and overrides
some methods in the basic distributed Ruby implementation to make it
use EventMachine's infrastructure instead of the normal networking
layer.  One could do the following, which is practically identical to
one of the examples for distributed Ruby:

  require 'emdrb'

  URI = "druby://localhost:8787"

  class TimeServer
    def get_current_time
      return(Time.now)
    end
  end

  $SAFE=1
  DRb.start_service(URI, TimeServer.new)
  DRb.thread.join

The corresponding client code could be made nearly identical:

  require 'emdrb'

  SERVER_URI="druby://localhost:8787"

  DRb.start_service
   
  timeserver = DRbObject.new_with_uri(SERVER_URI)
  puts timeserver.get_current_time 

Or it could be written to use of asynchronous calls:

  require 'emdrb'

  SERVER_URI="druby://localhost:8787"

  DRb.start_service
   
  timeserver = DRbObject.new_with_uri(SERVER_URI)

  EventMachine::next_tick do
    timeserver.async_call(:get_current_time).callback do |res|
      puts res
    end
  end

== REQUIREMENTS:

* Obviously, EMDRb requires EventMachine.

== INSTALL:

* Standard gem installation: 'sudo gem install' ought to do the trick.

Note that you will need the daemons gem ('sudo gem install daemons')
if you would like to run the rspec tests that are included with
EMDRb.  Daemons is not required to use EMDRb otherwise, and as such it
is not listed as a hard dependency in the gem install.

== LICENSE:

Copyright © 2008, 2009 Rafael R. Sevilla.  You can redistribute it
and/or modify it under the same terms as Ruby.  Please see the file
COPYING for more details.

$Id$

