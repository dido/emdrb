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
# Copyright © 2008, 2009, 2010 Rafael Sevilla
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
require 'emdrb'
require 'thread'

class LocalDeferrable
  include DRb::DRbEMSafe

  def df_tester(val)
    df = EventMachine::DefaultDeferrable.new
    df.succeed(val+1)
    return(df)
  end

  def df_tester_exception
    raise "test exception"
  end

  deferrable_method :df_tester
end

class TestEMDRb < Test::Unit::TestCase
  def self.global_setup
    DRb.start_service("druby://localhost:56789", LocalDeferrable.new)
    # Standard DRb server instance
    @@obj = DRbObject.new_with_uri("druby://localhost:12345")
    # EMDRb server instance
    @@obj2 = DRbObject.new_with_uri("druby://localhost:54321")
    @@obj3 = DRbObject.new_with_uri("druby://localhost:56789")
    @@pid1 = fork
    if @@pid1.nil?
      exec("ruby -Ilib examples/drbserver.rb drb")
    end

    @@pid2 = fork
    if @@pid2.nil?
      exec("ruby -Ilib examples/drbserver.rb emdrb")
    end
    sleep(0.5)
  end

  def self.global_teardown
    Process.kill(:TERM, @@pid1)
    Process.kill(:TERM, @@pid2)
    Process.wait
  end

  def setup
    unless defined?(@@expected_test_count)
      @@expected_test_count = (self.class.instance_methods.reject{ |method| method[0..3] != 'test'}).length
      self.class.global_setup
    end
  end

  def teardown
    if (@@expected_test_count-=1) == 0
      self.class.global_teardown
    end
  end

  def test_simple_sync
    assert_equal(1, @@obj.identity(1))
    assert_equal(3, @@obj.addtwo(1,2))
    assert_equal(1, @@obj2.identity(1))
    assert_equal(3, @@obj2.addtwo(1,2))
  end

  def test_block_sync
    val = 1
    @@obj.blockyield(1,2,3,4,5,6,7) { |x| val *= x }
    assert_equal(5040, val)

    val = 1
    @@obj2.blockyield(1,2,3,4,5,6,7) { |x| val *= x }
    assert_equal(5040, val)
  end

  def test_exceptions
    assert_raises(RuntimeError) do
      @@obj.raise_exception
    end

    assert_raises(RuntimeError) do
      @@obj2.raise_exception
    end
  end

  def test_async
#    q = Queue.new
#    EventMachine::next_tick do
#      @@obj.send_async(:identity, 1).callback do |data|
#        q << data
#      end
#    end
#    data = q.shift
#    assert_equal(1, data)

#    q = Queue.new
#    EventMachine::next_tick do
#      @@obj2.send_async(:identity, 1).callback do |data|
#        q << data
#      end
#    end
#    data = q.shift
#    assert_equal(1, data)
  end

  def test_variadic
    assert_equal(15, @@obj.sum(1,2,3,4,5))
    assert_equal(15, @@obj2.sum(1,2,3,4,5))
  end

  def test_deferrable
    assert_equal(15, @@obj.block_df([1,2,3,4,5]) { |x| x })
    assert_equal(15, @@obj2.block_df([1,2,3,4,5]) { |x| x })

    assert_raises(RuntimeError) do
      @@obj.block_df([1,2,3,4,5]) { |x| raise "an error" }
    end

    assert_raises(RuntimeError) do
      @@obj2.block_df([1,2,3,4,5]) { |x| raise "an error" }
    end
  end

  def test_local_df
    assert_equal(2, @@obj3.df_tester(1))
    assert_raises(RuntimeError) do
      @@obj3.df_tester_exception
    end
  end

end
