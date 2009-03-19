# -*- coding: utf-8 -*-
#
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

require File.join(File.dirname(__FILE__), %w[spec_helper])
require 'thread'

describe EMDRb do
  before do
    DRb.start_service
    @obj = DRbObject.new_with_uri("druby://localhost:12345")
  end

  after do
    DRb.stop_service
  end

  it "should be able to perform simple synchronous method calls" do
    @obj.identity(1).should == 1
    @obj.addtwo(1, 2).should == 3
  end

  it "should be able to perform synchronous method calls with a block" do
    val = 1
    @obj.blockyield(1,2,3,4,5,6,7) { |x| val *= x }
    val.should == 5040
  end

  it "should propagate exceptions to the client" do
    lambda do
      @obj.raise_exception
    end.should raise_error(RuntimeError) do |error|
      error.message.should == "This error should be expected"
    end
  end

  it "should be able to perform asynchronous method calls" do
    q = Queue.new
    EventMachine::next_tick do
      @obj.send_async(:identity, 1).callback do |data|
        q << data
      end
    end
    data = q.shift
    data.should == 1
  end

  it "should be able to perform asynchronous method calls with a passed block" do
    q = Queue.new
    val = 1
    EventMachine::next_tick do
      df = @obj.send_async(:blockyield, 1,2,3,4,5,6,7) { |x| val *= x; val }
      df.callback do |data|
        q << data
      end
    end
    data = q.shift
    data[0].should be_true
    val.should == 5040
  end

  it "should work with variadic methods" do
    @obj.sum(1,2,3,4,5).should == 15
  end

  it "should use deferrable methods correctly" do
    res = @obj.block_df([1,2,3,4,5]) { |x| x }
    res.should == 15
  end

  it "should propagate exceptions raised by a block in a deferrable method" do
    lambda do
      res = @obj.block_df([1,2,3,4,5]) { |x| raise "an error" }
    end.should raise_error(RuntimeError) do |error|
      error.message.should == "an error"
    end
  end
end

# EOF
