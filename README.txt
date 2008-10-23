emdrb
    by Rafael R. Sevilla <dido@imperium.ph>
    http://emdrb.rubyforge.org

== DESCRIPTION:

This is a distributed Ruby client and server which should work as a
drop-in replacement for the standard distributed Ruby implementation
available in the Ruby standard library.

== FEATURES/PROBLEMS:

This is a simple but working DRb server implementation that uses
EventMachine as its basis, rather than the default implementation that
uses traditional Ruby sockets.  This should be somewhat more scalable
than a server using the standard DRb library.

Obviously, this is a quick and dirty release, just to get something
out there, and of course it has a number of limitations.

* We still don't have a DRb client.  We use the client implementation
  of the standard DRb.
* No SSL support.
* No support for ACLs.
* No unit tests so it probably still has a lot of bugs.
* Many standard configuration options for DRb still unsupported

These and many other problems are scheduled to be addressed in the
next release.

== SYNOPSIS:

Creating a server using EMDRb has been made as close as possible to
making one with the standard library DRb:

  require 'emdrb'

  URI = "druby://localhost:8787"

  class TimeServer
    def get_current_time
      return(Time.now)
    end
  end

  $SAFE=1
  EMDRb.start_service(URI, TimeServer.new)
  EMDRb.thread.join

== REQUIREMENTS:

* Obviously, EMDRb requires EventMachine.

== INSTALL:

* Standard gem installation: 'sudo gem install' ought to do the trick.

== LICENSE:

Copyright (c) 2008 Rafael R. Sevilla.  You can redistribute it and/or
modify it under the same terms as Ruby.  Please see the file COPYING for
more details.



