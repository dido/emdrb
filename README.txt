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

EMDRb already supports the following features of the standard DRb:

* Clients and servers over TCP/IP
* Clients and servers over Unix domain sockets
* Standard distributed Ruby ACLs

It also has the following extensions, which derive from its basis in
EventMachine:

* Client-side asynchronous method calls
* EventMachine-aware server methods capable of asynchrony.

It is, however, not yet a complete replacement for the standard DRb:

* No SSL support.  To support this fully, EventMachine needs to have
  more comprehensive SSL/TLS support.
* RSpec tests are very basic, and need a lot more comprehensive work.
  They also don't work for some reason when run under Rake, but work
  just fine when run manually.
* Many standard configuration options for DRb still unsupported

These and many other problems are scheduled to be addressed in the
following releases.

== SYNOPSIS:

EMDRb basically reopens several classes, adds methods, and overrides other
methods in the basic distributed Ruby implementation to make it use
EventMachine's infrastructure instead of the traditional Ruby networking
code.  One could do the following, which is practically identical to one
of the examples for distributed Ruby:

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

If you want to install it manually, you can always download it at the
EMDRb project page at:

http://rubyforge.org/projects/emdrb

== LICENSE:

Copyright © 2008, 2009 Rafael R. Sevilla.  You can redistribute it
and/or modify it under the same terms as Ruby.  Please see the file
COPYING for more details.

$Id$

