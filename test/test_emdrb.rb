#
# Author:: Rafael R. Sevilla (mailto:dido@imperium.ph)
# Copyright:: Copyright (c) 2008 Rafael R. Sevilla
# Homepage:: http://emdrb.rubyforge.org/
# License:: GNU General Public License / Ruby License
#
# $Id$
#
#----------------------------------------------------------------------------
#
# Copyright (C) 2008 Rafael Sevilla
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
require 'test/unit'
require 'emdrb/emdrb'
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

class EMDRbTest < Test::Unit::TestCase
  def setup
    EMDRb.start_service("druby://:12345", TestServer.new)
  end

  def teardown
    EMDRb.thread.kill
  end

  def test_server
    o = DRbObject.new_with_uri("druby://localhost:12345")
    DRb.start_service
    assert_equal(1, o.identity(1))
    assert_equal(3, o.addtwo(1, 2))
    assert_raises(ArgumentError) do
      o.addtwo(1)
    end
    assert_equal(15, o.sum(1,2,3,4,5))
    val = 1
    o.blockyield(1,2,3,4,5,6,7) { |x| val *= x }
    assert_equal(5040, val)
  end

  def test_client
    o = EMDRb::DRbObject.new(nil, "druby://localhost:12345")
    q = Queue.new
    EventMachine::next_tick do
      o.send_async(:identity, 1).callback do |data|
        assert(data[0])
        assert_equal(1, data[1])
        q << data
      end
    end
    q.shift

    EventMachine::next_tick do
      val = 1
      df = o.send_async(:blockyield, 1,2,3,4,5,6,7) { |x| val *= x; val }
      df.callback do |data|
        assert(data[0])
        assert_equal(5040, val)
        q << data
      end
    end
    q.shift

  end

end
