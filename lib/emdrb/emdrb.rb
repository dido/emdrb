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
  DEFAULT_SAFE_LEVEL = 0

  ##
  # EventMachine server module for DRb.
  #
  module DRbServerProtocol
    ##
    # The front object for this server connection.
    attr_accessor :front
    ##
    # The load limit for this server connection.  Serialized objects
    # larger than this value will be rejected by the server with a
    # DRbConnError exception.  NOTE: the Ruby standard DRb will not
    # propagate this exception to the caller, but instead it will
    # occur internally, and the caller will receive a connection reset
    # as the server thread dies because there is no way for an exception
    # handler to handle the exception.  I don't think this is correct
    # behavior, and EMDRb will instead propagate the error to the caller.
    attr_accessor :load_limit

    ##
    # The maximum number of arguments that are allowed for this
    # server connection.  Method calls to this server which have
    # more arguments than this will result in an ArgumentError.
    attr_accessor :argc_limit

    ##
    # The ID-to-object mapping component mapping DRb object IDs to the
    # objects they refer to.
    attr_accessor :idconv

    ##
    # The server object which created this connection.
    attr_accessor :server

    ##
    # The safe level for this connection.
    attr_accessor :safe_level

    ##
    # The post initialization process sets up the default load
    # and argument length limits, the idconv object, the initial
    # state of the message packet state machine, clear the
    # message buffer, and empty the current request hash.
    def post_init
      @load_limit = DEFAULT_LOAD_LIMIT
      @argc_limit = DEFAULT_ARGC_LIMIT
      @safe_level = DEFAULT_SAFE_LEVEL
      @idconv = DRb::DRbIdConv.new
      @state = :ref
      @msgbuffer = ""
      @request = {}
      @server = @argv = @argc = nil
    end

    ##
    # Receive data from the caller.  This basically receives packets
    # containing objects marshalled using Ruby's Marshal::dump prefixed
    # by a length.  These objects are unmarshalled and processed by the
    # internal object request state machine.  If an error of any kind
    # occurs herein, the exception is propagated to the caller.
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
      rescue Exception => e
        send_reply(false, e)
      end
    end

    private

    ##
    # This method will dump an object +obj+ using Ruby's marshalling
    # capabilities.  It will make a proxy to the object instead if
    # the object is undumpable.  The dumps are basically data produced
    # by Marshal::dump prefixed by a 32-bit length field in network
    # byte order.
    #
    def dump(obj, error=false)
      if obj.kind_of? DRb::DRbUndumped
        obj = make_proxy(obj, error)
      end
      begin
        str = Marshal::dump(obj)
      rescue
        str = Marshal::dump(make_proxy(obj, error))
      end
      return([str.size].pack("N") + str)
    end

    ##
    # Create a proxy for +obj+ that is declared to be undumpable.
    #
    def make_proxy(obj, error=false)
      return(error ? Drb::DRbRemoteError.new(obj) : DRb::DRbObject.new(obj))
    end

    ##
    # Send a reply to the caller.  The return value for distributed Ruby
    # over the wire is the success as a boolean true or false value, followed
    # by a dump of the data.
    #
    def send_reply(succ, result)
      send_data(dump(succ) + dump(result, !succ))        
    end

    ##
    # This method will perform a method action if a block is not specified.
    #
    def perform_without_block
      if Proc == @front && @request[:msg] == :__drb_yield
        ary = (@request[:argv].size == 1) ? @request[:argv] : [@request[:argv]]
        return(ary.collect(&@front)[0])
      end
      return(@front.__send__(@request[:msg], *@request[:argv]))
    end

    ##
    # block_yield method lifted almost verbatim from InvokeMethod18Mixin
    # from the standard distributed Ruby.  Obviously, since EventMachine
    # doesn't work with Ruby 1.6.x, we don't care about the 1.6 version...
    #
    def block_yield(x)
      if x.size == 1 && x[0].class == Array
        x[0] = DRb::DRbArray.new(x[0])
      end
      block_value = @request[:block].call(*x)
    end

    ##
    # Perform with a method action with a specified block.
    #
    def perform_with_block
      @front.__send__(@request[:msg], *@request[:argv]) do |*x|
        jump_error = nil
        begin
          block_value = block_yield(x)
        rescue LocalJumpError
          jump_error = $!
        end
        if jump_error
          case jump_error.reason
          when :retry
            retry
          when :break
            break(jump_error.exit_value)
          else
            raise jump_error
          end
        end
        block_value
      end
    end

    ##
    # Perform a method action.  This handles the safe level invocations.
    #
    def perform
      result = nil
      succ = false
      begin
        @server.check_insecure_method(@front, @request[:msg])
        if $SAFE < @safe_level
          info = Thread.current['DRb']
          result = Thread.new {
            Thread.current['DRb'] = info
            $SAFE = @safe_level
            (@request[:block]) ? perform_with_block : perform_without_block
          }.value
        else
          result = (@request[:block]) ? perform_with_block :
            perform_without_block
          succ = true
          if @request[:msg] == :to_ary && result.class == Array
            result = DRb::DRbArray.new(result)
          end
        end
      rescue StandardError, ScriptError, Interrupt
        result = $!
      end
      return([succ, result])
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
        @state = (@argc == 0) ? :block : :argv
      when :argv
        @argv << @request[:argv]
        @argc -= 1
        if @argc < 1
          @state = :block
        end
      when :block
        @request[:argv] = @argv        
        @state = :ref
        send_reply(*perform)
        @request = {}
        @argc = @argv = nil
      else
        @state = :ref
      end
    end

    ##
    # Load a serialized object.
    def obj_load(message)
      begin
        return(Marshal::load(message))
      rescue NameError, ArgumentError
        return(DRb::DRbUnknown.new($!, message))
      end
    end

  end

  class DRbServer < DRb::DRbServer
    def initialize(uri=nil, front=nil, config_or_acl=nil)
      if Hash === config_or_acl
	config = config_or_acl.dup
      else
	acl = config_or_acl || @@acl
	config = {
	  :tcp_acl => acl
	}
      end

      @uri = (uri.nil?) ? "druby://:0" : uri
      @config = self.class.make_config(config)
      @front = front
      @idconv = @config[:idconv]
      @safe_level = @config[:safe_level]
      @thread = run
      EMDRb.regist_server(self)
    end

    private

    def self.host_inaddr_any
      host = Socket::gethostname
      begin
        host = Socket::gethostbyname(host)[0]
      rescue
        host = "localhost"
      end
      infos = Socket::getaddrinfo(host, nil,
                                  Socket::AF_UNSPEC,
                                  Socket::SOCK_STREAM,
                                  0,
                                  Socket::AI_PASSIVE)
      family = infos.collect { |af, *_| af }.uniq
      case family
      when ['AF_INET']
        return("0.0.0.0")
      when ['AF_INET6']
        return("::")
      else
        raise "Unknown network class"
      end
    end

    def run
      Thread.start do
        host, port, opt = EMDRb::parse_uri(@uri)
        if host.size == 0
          host = self.class.host_inaddr_any
        end
        EventMachine::run do
          EventMachine::start_server(host, port, DRbServerProtocol) do |conn|
            Thread.current['DRb'] = { 'client' => conn, 'server' => self }
            conn.front = @front
            conn.load_limit = @config[:load_limit]
            conn.argc_limit = @config[:argc_limit]
            conn.idconv = @config[:idconv]
            conn.server = self
            conn.safe_level = self.safe_level
          end
        end
      end
    end

  end

  def parse_uri(uri)
    if uri =~ /^druby:\/\/(.*?):(\d+)(\?(.*))?$/
      host = $1
      port = $2.to_i
      option = $4
      [host, port, option]
    else
      unless uri =~ /^druby:/
        raise DRb::DRbBadScheme.new(uri)
      end
      raise DRb::DRbBadURI.new('can\'t parse uri:' + uri)
    end
  end
  module_function :parse_uri

  @primary_server = nil

  def start_service(uri=nil, front=nil, config=nil)
    @primary_server = DRbServer.new(uri, front, config)
  end
  module_function :start_service

  attr_accessor :primary_server
  module_function :primary_server=, :primary_server

  @server = {}
  def regist_server(server)
    @server[server.uri] = server
    Thread.exclusive do
      @primary_server = server unless @primary_server
    end
  end
  module_function :regist_server

  ##
  # Get the 'current' server.
  #
  # In the context of execution taking place within the main
  # thread of a dRuby server (typically, as a result of a remote
  # call on the server or one of its objects), the current
  # server is that server.  Otherwise, the current server is
  # the primary server.
  #
  # If the above rule fails to find a server, a DRbServerNotFound
  # error is raised.
  def current_server
    drb = Thread.current['DRb'] 
    server = (drb && drb['server']) ? drb['server'] : @primary_server 
    raise DRb::DRbServerNotFound unless server
    return server
  end
  module_function :current_server

  ##
  # Get the thread of the primary server.
  #
  # This returns nil if there is no primary server.  See #primary_server.
  def thread
    @primary_server ? @primary_server.thread : nil
  end
  module_function :thread

end
