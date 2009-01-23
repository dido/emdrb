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
# This tests the EMDRb server implementation against the standard DRb
# client.
#
#require File.join(File.dirname(__FILE__), %w[spec_helper])
require File.join(File.dirname(__FILE__), %w[spec_common])
require 'drb'       # yes, that's right, we use the STANDARD DRb here!
require 'thread'

Thread.abort_on_exception = true

describe "EMDRb Server" do
  it_should_behave_like "DRb basics"

  before(:all) do
    # but we start the *server* with EMDRb
    system(File.join(File.dirname(__FILE__), "drbserver.rb emdrb"))
    DRb.start_service
    @obj = DRbObject.new_with_uri("druby://localhost:12345")
  end

  after(:all) do
    pid = File.open(File.join(File.dirname(__FILE__), "drbserver.pid")) { |fp| fp.read.to_i }
    Process.kill("SIGTERM", pid)
  end

  it "should work with variadic methods" do
    @obj.sum(1,2,3,4,5).should == 15
  end

end
