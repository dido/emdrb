#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
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

Thread.abort_on_exception = true
if ARGV[0] == "emdrb"
  $LOAD_PATH << File.join(File.dirname(__FILE__), '../lib/')
  require 'emdrb'
elsif ARGV[0] == "drb"
  require 'drb'
else
  raise "specify emdrb or drb on the command line"
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

if ARGV[0] == "emdrb"
  class TestServer
    include DRb::DRbEMSafe
    include EventMachine::Deferrable

    deferrable_method :block_df

    ##
    # Simple example of a deferrable method structured as a state
    # machine.
    def block_df(data, state={:index => 0, :retval => 0 }, &block)
      if state[:index] >= data.length
        self.set_deferred_status(:succeeded, state[:retval])
        return(self)
      end

      df = yield data[state[:index]]
      df.callback do |result|
        state[:retval] += result
        state[:index] += 1
        self.block_df(data, state, &block)
      end
      df.errback do |res|
        df.fail(res)
      end
      return(self)
    end
  end
end


DRb.start_service("druby://:12345", TestServer.new)
DRb.thread.join
