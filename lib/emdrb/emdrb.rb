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
require 'eventmachine'
require 'thread'
require 'drb'

module DRb
  DEFAULT_ARGC_LIMIT = 256
  DEFAULT_LOAD_LIMIT = 256 * 102400
  DEFAULT_SAFE_LEVEL = 0

  ##
  # Common protocol elements for distributed Ruby, used by both the
  # client and server.
  #
  module DRbProtocolCommon
    ##
    # This method will dump an object +obj+ using Ruby's marshalling
    # capabilities.  It will make a proxy to the object instead if
    # the object is undumpable.  The dumps are basically data produced
    # by Marshal::dump prefixed by a 32-bit length field in network
    # byte order.
    #
    def dump(obj, error=false)
      if obj.kind_of? DRbUndumped
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
      return(error ? DRbRemoteError.new(obj) : DRbObject.new(obj))
    end

    ##
    # Receive data from the caller.  This basically receives packets
    # containing objects marshalled using Ruby's Marshal::dump prefixed
    # by a length.  These objects are unmarshalled and processed by the
    # internal object request state machine which should be represented by
    # a receive_obj method from within the mixin.
    def receive_data_raw(data)
      @msgbuffer << data
      while @msgbuffer.length > 4
        length = @msgbuffer.unpack("N")[0]
        if length > @load_limit
          raise DRbConnError, "too large packet #{length}"
        end

        if @msgbuffer.length < length - 4
          # not enough data for this length, return to event loop
          # to wait for more.
          break
        end
        length, message, @msgbuffer = @msgbuffer.unpack("Na#{length}a*")
        receive_obj(obj_load(message))
      end
    end

    ##
    # Load a serialized object.
    def obj_load(message)
      begin
        return(Marshal::load(message))
      rescue NameError, ArgumentError
        return(DRbUnknown.new($!, message))
      end
    end
  end

  ##
  # EventMachine server module for DRb.
  #
  module DRbServerProtocol
    include DRbProtocolCommon
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

    private

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

    ##
    # This is the main state machine that processes distributed Ruby calls.
    # A DRb client basically sends several pieces of data in sequence, each
    # of which corresponds to a state of this machine.
    #
    # 1. :ref - this gives a reference to a DRb server running on the
    #    caller, mainly used to provide a mechanism for accessing undumpable
    #    objects on the caller.
    # 2. :msg - a symbol giving the method to be called on this server.
    # 3. :argc - an integer count of the number of arguments on the caller.
    # 4. :argv - repeats an :argc number of times, the actual arguments
    #    sent by the caller.
    # 5. :block - the block passed by the caller (generally a DRbObject
    #    wrapping a Proc object).
    #
    def receive_obj(obj)
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
    # This version of receive_data will propagate any exceptions thrown
    # by receive_data_raw back to the caller.  This includes load limit
    # errors and other miscellanea.
    def receive_data(data)
      begin
        return(receive_data_raw(data))
      rescue Exception => e
        return(send_reply(false, e))
      end
    end

  end

  ##
  # Class representing a drb server instance.  This subclasses DRb::DRbServer
  # for brevity.  DRbServer instances are normally created indirectly using
  # either EMDRb.start service (which emulates DRb.start_service) or via
  # EMDRb.start_drbserver (designed to be called from within an event loop).
  class DRbServer
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
      EventMachine::next_tick do
        @thread = Thread.current
      end
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

    public

    ##
    # Start a DRb server from within an event loop.
    #
    def start_drb_server
      @thread = Thread.current
      host, port, opt = DRb::parse_uri_drb(@uri)
      if host.size == 0
        host = self.class.host_inaddr_any
      end
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

  def parse_uri_drb(uri)
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
  module_function :parse_uri_drb

  @eventloop = nil

  ##
  # This is the 'bare bones' start_service which can be used to
  # start a DRb service from within an existing event loop.
  def start_drbserver(uri=nil, front=nil, config=nil)
    serv = DRbServer.new(uri, front, config)
    serv.start_drb_server
    return(serv)
  end
  module_function :start_drbserver

  ##
  # This start_service emulates DRb#start_service.
  #
  def start_service(uri=nil, front=nil, config=nil)
    unless EventMachine::reactor_running?
      @eventloop = Thread.new do
        EventMachine::run do
          # Start an empty event loop.  The DRb server(s) will be started
          # by EM#next_tick calls.
        end
      end
    end
    queue = Queue.new
    EventMachine::next_tick do
      queue << self.start_drbserver(uri, front, config)
    end
    serv = queue.shift
    @primary_server = serv
    DRb.regist_server(serv)
    return(serv)
  end
  module_function :start_service

  ##
  # Client protocol module 
  module DRbClientProtocol
    include DRbProtocolCommon

    attr_accessor :ref
    attr_accessor :msg_id
    attr_accessor :args
    attr_accessor :block
    attr_accessor :df

    def post_init
      @msgbuffer = ""
      @idconv = DRbIdConv.new
      @load_limit = DEFAULT_LOAD_LIMIT
    end

    def connection_completed
      @connected = true
      send_request(@ref, @msg_id, @args, @block)
      @state = :succ
      @succ = nil
      @result = nil
    end

    def send_request(ref, msgid, arg, block)
      ary = []
      ary.push(dump(ref.__drbref))
      ary.push(dump(msg_id.id2name))
      ary.push(dump(arg.length))
      arg.each do |e|
	ary.push(dump(e))
      end
      ary.push(dump(block))
      send_data(ary.join(''))
    end

    def receive_obj(obj)
      if @state == :succ
        @succ = obj
        @state = :result
      else
        @result = obj
        @state = :succ
        @df.set_deferred_status(:succeeded, [@succ, @result])
        # close the connection after the call succeeds.
        close_connection
      end
    end

    def receive_data(data)
      return(receive_data_raw(data))
    end
  end

  ##
  # Object wrapping a reference to a remote drb object.
  #
  # Method calls on this object are relayed to the remote object
  # that this object is a stub for.
  class DRbObject
    def initialize(obj, uri=nil)
      @uri = nil
      @ref = nil
      if obj.nil?
	return if uri.nil?
        @uri = uri
        ref = nil
        @host, @port, @opt = DRb::parse_uri_drb(@uri)
      else
	@uri = uri ? uri : (DRb.uri rescue nil)
        @ref = obj ? DRb.to_id(obj) : nil
      end
    end

    ##
    # Perform an asynchronous call to the remote object.  This can only
    # be used from within the event loop.  It returns a deferrable to which
    # callbacks can be attached.
    def send_async(msg_id, *a, &b)
      df = EventMachine::DefaultDeferrable.new
      EventMachine.connect(@host, @port, DRbClientProtocol) do |c|
        c.ref = self
        c.msg_id = msg_id
        c.args = a
        c.block = b
        c.df = df
      end
      return(df)
    end

    ##
    # Route method calls to the referenced object.  This synchronizes
    # an asynchronous call by using a Queue to synchronize the DRb
    # event thread with the calling thread, so use of this mechanism,
    # to make method calls within an event loop will thus result in a
    # threading deadlock!  Use the send_async method if you want to
    # use EMDRb from within an event loop.
    def method_missing(msg_id, *a, &b)
      if DRb.here?(@uri)
	obj = DRb.to_obj(@ref)
	DRb.current_server.check_insecure_method(obj, msg_id)
	return obj.__send__(msg_id, *a, &b) 
      end

      q = Queue.new
      EventMachine::next_tick do
        df = self.send_async(msg_id, *a, &b)
        df.callback { |data| q << data }
      end
      succ, result = q.shift

      if succ
        return result
      elsif DRbUnknown === result
        raise result
      else
        bt = self.class.prepare_backtrace(@uri, result)
	result.set_backtrace(bt + caller)
        raise result
      end
    end

  end

end
