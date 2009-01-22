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
require 'drb'
Thread.abort_on_exception = true

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

describe EMDRb, "Server" do
  before(:all) do
    DRb.start_service("druby://:12345", TestServer.new)
    @obj = DRbObject.new_with_uri("druby://localhost:12345")
  end

  it "should handle basic method calls from the standard DRb client" do
    @obj.identity(1).should == 1
    @obj.addtwo(1, 2).should == 3
  end

  it "should raise an error if insufficient arguments are provided to a remote method call" do
    lambda { @obj.addtwo(1) }.should raise_error(ArgumentError)
  end

  it "should work with variadic methods" do
    @obj.sum(1,2,3,4,5).should == 15
  end

  it "should allow blocks to be passed" do
    val = 1
    @obj.blockyield(1,2,3,4,5,6,7) { |x| val *= x }
    val.should == 5040
  end

  after(:all) do
    DRb.thread.kill
  end

end
