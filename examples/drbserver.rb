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
  port = 54321
elsif ARGV[0] == "drb"
  require 'drb'
  port = 12345
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

  def raise_exception
    raise "This error should be expected"
  end
end

if ARGV[0] == "emdrb"
  class TestServer
    include DRb::DRbEMSafe

    deferrable_method :block_df

    ##
    # Simple example of a deferrable method structured as a state
    # machine.  This method sums values of the data array as they
    # are returned by the caller.  The similarity of this function
    # to a tail-recursive, continuation-passing style version of
    # the same should be obvious...
    def block_df(data, state={:index => 0, :retval => 0, :df => nil}, &block)
      state[:df] ||= EventMachine::DefaultDeferrable.new
      if state[:index] >= data.length
        state[:df].set_deferred_status(:succeeded, state[:retval])
        return(state[:df])
      end

      df = yield data[state[:index]]
      df.callback do |result|
        state[:retval] += result
        state[:index] += 1
        self.block_df(data, state, &block)
      end
      df.errback do |res|
        state[:df].fail(res)
      end
      return(state[:df])
    end
  end
else
  class TestServer
    # This is a fake implementation of block_df to be used by the standard
    # DRb so that the same tests will run against either.
    def block_df(vals, &block)
      return(vals.inject(0) { |x,y| x + block.call(y) })
    end

  end
end

DRb.start_service("druby://127.0.0.1:#{port}", TestServer.new)
DRb.thread.join
