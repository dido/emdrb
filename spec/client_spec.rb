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
require File.join(File.dirname(__FILE__), %w[spec_common])
require 'thread'

Thread.abort_on_exception = true

describe EMDRb, "Client" do
  it_should_behave_like "DRb basics"

  before do
    @pid = fork
    if @pid.nil?
      exec(File.join(File.dirname(__FILE__), "drbserver.rb drb"))
    end
    DRb.start_service
    @obj = DRb::DRbObject.new(nil, "druby://localhost:12345")
  end

  after do
    DRb.stop_service
    Process.kill("SIGTERM", @pid)
    Process.waitpid(@pid)
  end

  it "should be able to perform asynchronous method calls" do
    q = Queue.new
    EventMachine::next_tick do
      @obj.send_async(:identity, 1).callback do |data|
        q << data
      end
    end
    data = q.shift
    data[0].should be_true
    data[1].should == 1
  end

  it "should be able to perform asynchronous method calls with a passed block" do
    EventMachine::next_tick do
      val = 1
      df = @obj.send_async(:blockyield, 1,2,3,4,5,6,7) { |x| val *= x; val }
      df.callback do |data|
        data[0].should be_true
        val.should == 5040
      end
    end
  end

end
