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
require 'eventmachine'
require 'drb'

module EMDRb
  DEFAULT_ARGC_LIMIT = 256
  DEFAULT_LOAD_LIMIT = 256 * 102400

  module Server
    attr_accessor :front

    def post_init
      @load_limit = DEFAULT_LOAD_LIMIT
      @argc_limit = DEFAULT_ARGC_LIMIT
      @idconv = DRb::DRbIdConv.new
      @state = :ref
      @msgbuffer = ""
      @request = {}
      @argv = @argc = nil
    end

    def dump(obj, error=false)
      str = Marshal::dump(obj)
      return([str.size].pack("N") + str)
    end

    def send_reply(succ, result)
      send_data(dump(succ) + dump(result, !succ))
    end

    def perform_without_block(args)
      succ, result = begin
                       [true, @front.__send__(@request[:msg], *@request[:argv])]
                     rescue StandardError, ScriptError, Interrupt
                       [false, $!]
                     end
      send_reply(succ, result)
    end

    def to_obj(ref)
      if ref.nil?
        return(@front)
      end
      return(@idconv.to_obj(ref))
    end

    def add_obj(obj)
      @request[@state] = obj
      case @state
      when :ref
        @request[:ro] = to_obj(@request[:ref])
        @state = :msg
      when :msg
        @request[:msg] = @request[:msg].intern
        @state = :argc
      when :argc
        @argc = @request[:argc]
        if @argc_limit < @argc
          raise ArgumentError, 'too many arguments'
        end
        @argv = []
        @state = :argv
      when :argv
        @argv << @request[:argv]
        @argc -= 1
        if (@argc == 0)
          @request[:argv] = @argv
          @state = :block
        end
      when :block
        @state = :ref
        perform(@request)
        @request = {}
        @argc = @argv = nil
      else
        @state = :ref
      end
    end

    ##
    # Load a serialized object.
    def objload(message)
      begin
        return(Marshal::load(message))
      rescue NameError, ArgumentError
        return(DRb::DRbUnknown.new($!, message))
      end
    end

    def receive_data(data)
      begin
        @msgbuffer << data
        while @msgbuffer.length > 4
          length = @msgbuffer.unpack("N")[0]
          if length > @load_limit
            raise DRb::DRbConnError, "too large packet #{length}"
          end

          if @msgbuffer.length < length - 4
            # not enough data for this length, return to event loop
            # to wait for more.
            break
          end
          length, message, @msgbuffer = @msgbuffer.unpack("Na#{length}a*")
          add_obj(obj_load(message))
        end
      end
    rescue Exception => e
      send_reply(false, e)
    end
  end

  def parse_uri(uri)
    if uri =~ /^druby:\/\/(.*?):(\d+)(\?(.*))?$/
      host = $1
      port = $2.to_i
      option = $4
      [host, port, option]
    else
      raise(DRb::DRbBadScheme, uri) unless uri =~ /^druby:/
      raise(DRb::DRbBadURI, 'can\'t parse uri:' + uri)
    end
  end
  module_function :parse_uri

  def start_service(uri, front)
    host, port, opt = parse_uri(uri)
    EventMachine::run do
      EventMachine::start_server(host, port, Server) do |conn|
        conn.front = front
      end
    end
  end

  module_function :start_service

end

class Test
  def test(x)
    return(x.inject { |a, b| a += b })
  end
end

EMDRb.start_service("druby://0.0.0.0:12345", Test.new)
