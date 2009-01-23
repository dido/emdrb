#!/usr/bin/env ruby
# Author:: Rafael R. Sevilla (mailto:dido@imperium.ph)
# Copyright:: Copyright © 2008, 2009 Rafael R. Sevilla
# Homepage:: http://emdrb.rubyforge.org/
# License:: GNU General Public License / Ruby License
#
# $Id$
#
#----------------------------------------------------------------------------
#
# Copyright © 2008, 2009 Rafael Sevilla
# This file is part of EMDRb
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of either: 1) the GNU General Public License
# as published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version; or 2) Ruby's License.
# 
# See the file COPYING for complete licensing information.
#----------------------------------------------------------------------------
#
# This is the DRb server that should be run by the specs, and can execute
# using either the standard DRb or EMDRb depending on what is being tested.
#
require 'daemons'

if ARGV[0] == "emdrb"
  $LOAD_PATH << File.join(File.dirname(__FILE__), '../lib/')
  require 'emdrb'
elsif ARGV[0] == "drb"
  require 'drb'
else
  raise "specify emdrb or drb on the command line"
end

if ARGV[1].nil?
  pidfile = File.expand_path(File.join(File.dirname(__FILE__), "drbserver.pid"))
  if File.exist?(pidfile)
    exit(0)
  end
#  logfile = File.expand_path(File.join(File.dirname(__FILE__), "drbserver.log"))
  Daemonize.daemonize
  pid = Process.pid
  File.open(pidfile, "w") { |fp| fp.write(pid.to_s) }

  handler = lambda do
    File.delete(pidfile)
    exit(0)
  end

  trap("SIGTERM", handler)
  trap("SIGINT", handler)
end

class TestServer
  def identity(x)
    return(x)
  end

  def addtwo(x, y)
    return(x+y)
  end

  def sum(*vals)
    return(vals.inject(0) { |x,y| x + y })
  end

  def blockyield(*vals)
    vals.each do |x|
      yield x
    end
  end
end



DRb.start_service("druby://:12345", TestServer.new)
DRb.thread.join
