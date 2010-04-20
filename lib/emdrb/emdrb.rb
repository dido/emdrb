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
require 'eventmachine'
require 'thread'
require 'drb'

module DRb
  DEFAULT_ARGC_LIMIT = 256
  DEFAULT_LOAD_LIMIT = 256 * 102400
  DEFAULT_SAFE_LEVEL = 0

  ##
  # The DRbEMSafe module allows the designation of certain methods as
  # 'deferrable methods' which are run from within the event loop rather
  # than within a thread.  It gives one the ability to circumvent the
  # sugaring and black magic that EMDRb does in order to provide the
  # complete illusion that remote objects are the same as local ones,
  # most especially with respect to blocks.  This may also provide more
  # performance if one is using a method that itself makes use of
  # Deferrables to accomplish the job.
  #
  # There are certain rules that deferrable methods must obey:
  #
  # 1. They must always return a Deferrable to their caller.  This
  #    Deferrable should succeed if the method returns a normal value,
  #    passing its result as a parameter to any of its callbacks.
  # 2. Exceptions must be caught and the Deferrable they return must
  #    fail, with the exception object passed as a parameter to its
  #    errbacks.
  # 3. Blocks passed to the deferrable method should always return a
  #    Deferrable, which again should succeed when the value of the
  #    block becomes available.
  # 
  module DRbEMSafe
    module ClassMethods
      ##
      # Mark the method as a deferrable method.  Such a method must always
      # return an object which includes EventMachine::Deferrable.  A block
      # passed to such a method returns a deferrable whenever it is invoked,
      # by doing a direct call to the block or using yield, and the code
      # for the deferrable method must take this into account.
      def deferrable_method(method_name)
        @deferrable_methods ||= {}
        @deferrable_methods[method_name] = true
      end

      def deferrable_method?(method_name)
        return(@deferrable_methods.has_key?(method_name))
      end

    end

    def self.included(base)
      base.extend(ClassMethods)
    end
  end

  ##
  # Used to wrap Proc objects so that they can be safely called from
  # deferrable methods.  This makes any invocation of the block an
  # asynchronous call that returns a Deferrable rather than calling
  # the block synchronously, which will result in a threading deadlock
  # if this is performed in the main event loop.  This mechanism is
  # used to provide facilities for deferrable methods which run within
  # the master event loop.
  class DRbProcWrapper
    def initialize(block)
      @block = block
    end

    ##
    # Initiate an asynchronous call to the block this is wrapping around.
    # Returns a deferrable.
    def call(*args)
      if args.size == 1 && args[0].class == Array
        args[0] = DRbArray.new(args[0])
      end
      return(@block.send_async(:call, *args))
    end

    ##
    # Return a Proc that will do an asynchronous call to the underlying
    # object.
    def to_proc
      return(Proc.new { |args| self.call(args) })
    end
  end

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
    # The peer address for this connection.
    attr_accessor :peer_addr

    ##
    # The URI for this connection
    attr_accessor :uri

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
      @peer_addr = @server = @argv = @argc = nil
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
    # For symmetry with perform_with_block, this method returns a deferrable
    # instead of the actual value or exception as the case may be.  It will
    # also further execute the method call in its own independent thread
    # and safe level invocations are also taken care of herein.
    def perform_without_block
      info = Thread.current['DRb']
      req = @request
      op = lambda do
        Thread.current['DRb'] = info
        if $SAFE < @safe_level
          $SAFE = @safe_level
        end
        begin
          if Proc == req[:ro] && req[:msg] == :__drb_yield
            ary = (req[:argv].size == 1) ? req[:argv] :
              [req[:argv]]
            [true, ary.collect(&@front)[0]]
          else
            r = req[:ro].__send__(req[:msg], *req[:argv])
            [true, r]
          end
        rescue
          [false, $!]
        end
      end
      return(op)
    end

    ##
    # block_yield method lifted almost verbatim from InvokeMethod18Mixin
    # from the standard distributed Ruby.  Obviously, since EventMachine
    # doesn't work with Ruby 1.6.x, we don't care about the 1.6 version...
    # Since this performs a synchronous DRb call, we need to execute this
    # within a thread of its own.
    def block_yield(req, x)
      if x.size == 1 && x[0].class == Array
        x[0] = DRbArray.new(x[0])
      end
      block_value = req[:block].call(*x)
      return(block_value)
    end

    ##
    # Perform with a method action with a specified block.  We have to
    # do the action within a thread of its own in order to avoid deadlock
    # due to the call in block_yield above, which uses synchronous calls.
    # I suppose there must be a way to do it without using threads (possibly
    # by using call/cc perhaps?), but I suppose this should be okay.
    def perform_with_block
      info = Thread.current['DRb']
      req = @request
      op = lambda do
        Thread.current['DRb'] = info
        if $SAFE < @safe_level
          $SAFE = @safe_level
        end
        begin
          r = req[:ro].__send__(req[:msg], *req[:argv]) do |*x|
            jump_error = nil
            block_value = nil
            begin
              block_value = block_yield(req, x)
            rescue LocalJumpError
              jump_error = $!
            end
            if jump_error
              case jump_error.reason
              when :break
                break(jump_error.exit_value)
              else
                raise jump_error
              end
            end
            block_value
          end
          [true, r]
        rescue Exception => e
          [false, e]
        end
      end
      return(op)
    end

    ##
    # Perform a method action.  This returns a deferrable that gets
    # posted to succeeded or failed depending on whether the method
    # call did not raise or raised an exception while it was being
    # executed.
    #
    def perform
      @server.check_insecure_method(@request[:ro], @request[:msg])
      if @request[:ro].kind_of?(DRbEMSafe) &&
          @request[:ro].class.deferrable_method?(@request[:msg])
        # A deferrable method will return an actual Deferrable that we
        # can use instead.
        begin
          return(@request[:ro].__send__(@request[:msg],
                                        *@request[:argv],
                                        &DRbProcWrapper.new(@request[:block])))
        rescue
          df = EventMachine::DefaultDeferrable.new
          df.fail($!)
          return(df)
        end
      end
      df = EventMachine::DefaultDeferrable.new
      op = (@request[:block]) ? perform_with_block : perform_without_block
      callback = lambda do |res|
        succ, val = res
        df.set_deferred_status((succ) ? :succeeded : :failed, val)
      end

      EventMachine::defer(op, callback)
      return(df)
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
        df = perform
        df.callback do |result|
          if @request[:msg] == :to_ary && result.class == Array
            result = DRb::DRbArray.new(result)
          end
          send_reply(true, result)
        end
        df.errback do |error|
          send_reply(false, error)
        end
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
  # The default DRb transport, which performs communication over a TCP
  # socket.  These protocol objects are used in a different way from the
  # way they are used internally by the standard DRb.  In the standard
  # DRb, open_server is a class method.  Here, it is an instance method
  # that is called when the server object is started.
  class DRbTCPSocket
    private

    def self.host_inaddr_any(host)
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

    attr_reader :uri
    attr_reader :option

    def initialize(uri, config={})
      @uri = (uri.nil?) ? 'druby://:0' : uri
      @host, @port, @option = self.class.parse_uri(@uri)
      @host.untaint
      @port.untaint
      @config = config
      @acl = config[:tcp_acl]
      if @host.size == 0
        @host = self.class.getservername
        @connhost = self.class.host_inaddr_any(@host)
      end
    end

    ##
    # This method starts a TCP server using EventMachine.
    def start_server(prot)
      # If start_server is called several times, only the one started
      # server will be made.
      if @conndesc
        return(@conndesc)
      end
      @conndesc = EventMachine::start_server(@host, @port, prot) do |conn|
        # Obtain the address of the peer, and check it against
        # any ACLs that might have been specified.
        peeraddr = Socket.unpack_sockaddr_in(conn.get_peername)[1]
        @config[:reverse_dns] = true
        if @config[:reverse_dns]
          a = Socket.gethostbyname(peeraddr)
          peeraddr = begin
                       [Socket.gethostbyaddr(a[3], a[2])[0], peeraddr]
                     rescue
                       [nil, peeraddr]
                     end
        else
          peeraddr = [nil, peeraddr]
        end
        conn.peer_addr = [nil, nil] + peeraddr

        if block_given?
          yield conn
        end

        if @acl && !@acl.allow_addr?(conn.peer_addr)
          conn.close_connection
        end

      end
      # NOTE: This is an undocumented method in EventMachine.  Revise
      # as necessary when we receive feedback from the EventMachine
      # developers on the canonical way to determine the real port number
      # if port 0 was specified in start_server.
      addr = Socket.unpack_sockaddr_in(EventMachine.get_sockname(@conndesc))
      @port = addr[0] if @port == 0
      @uri = "druby://#{@host}:#{@port}"
      return(@conndesc)
    end

    ##
    # This method makes a client connection using EventMachine
    def client_connect(prot)
      EventMachine.connect(@host, @port, prot) do |c|
        if block_given?
          yield c
        end
      end
    end


    ##
    # This method closes a server that has been started using this
    # protocol object instance.
    def stop_server
      if @conndesc
        @conndesc = nil
        if EventMachine::reactor_running?
          EventMachine::stop_server(@conndesc)
        end
      end
    end
  end

  ##
  # Module managing the underlying network transport(s) used by EMDRb.
  # This is analogous to the DRbProtocol module used by the original
  # DRb.  The network transport classes must define the following
  # class method:
  #
  #   [uri_option(uri, config)] Take a URI, possibly containing an option
  #                             component (e.g. a trailing '?param=val'), 
  #                             and return a [uri, option] tuple.
  #
  # A network transport class is instantiated whenever an EMDRb client
  # or server starts operation, provided with the URI and any configuration
  # options.  The transport initialize method should raise a DRbBadScheme
  # exception if the URI is invalid.  This is how the DRbTransport module
  # determines which transport implementation serves a particular URI.
  #
  # The transport class instance must provide the following methods:
  #
  #   [start_server(prot)] Open a server listening at the URI specified when
  #                        the transport instance was created using the
  #                        protocol handler module or class +prot+.  A block
  #                        passed here will be called whenever a connection is
  #                        made to the server, just after the post_init method
  #                        of the handler is called.
  #   [client_connect(prot)] Open a client connection to the URI specified when
  #                          the when the transport instance was created, using
  #                          the protocol handler module or class +prot+.  A
  #                          block passed here will be called when the
  #                          connection has been initiated, just after the
  #                          post_init method of the handler is called.
  #   [stop_server] Stop a server that was started with start_server.
  # 
  module DRbTransport
    @transports = [DRbTCPSocket]

    def add_transport(tr)
      @transports.push(tr)
    end
    module_function :add_transport

    ##
    # Rather than open_server, EMDRb uses this protocol factory method
    # to create a protocol object instance that DRbServer and DRbClient
    # can use later on when they want to connect.
    def factory(uri, config, first=true)
      @transports.each do |t|
        begin
          return(t.new(uri, config))
	rescue DRbBadScheme
	end
      end
      if first && (config[:auto_load] != false)
	auto_load(uri, config)
	return factory(uri, config, false)
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end
    module_function :factory

    ##
    # Parse +uri+ into a [uri, option] pair.
    #
    # The DRbTransport module asks each registered transport class in turn to
    # try to parse the URI.  Each transport signals that it does not handle
    # that URI by raising a DRbBadScheme error.  If no transport recognizes
    # the URI, then a DRbBadURI error is raised.  
    def uri_option(uri, config, first=true)
      @transports.each do |t|
	begin
	  uri, opt = t.uri_option(uri, config)
	  # opt = nil if opt == ''
	  return uri, opt
	rescue DRbBadScheme
	end
      end
      if first && (config[:auto_load] != false)
	auto_load(uri, config)
        return uri_option(uri, config, false)
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end
    module_function :uri_option

    def auto_load(uri, config)  # :nodoc:
      if uri =~ /^drb([a-z0-9]+):/
	require("emdrb/#{$1}") rescue nil
      end
    end
    module_function :auto_load

  end

  ##
  # Class representing a drb server instance.  DRbServer instances are
  # normally created indirectly using either DRb.start_service or
  # EMDRb.start_drbserver (designed to be called from within an event
  # loop).
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

      @config = self.class.make_config(config)
      @protocol = DRbTransport.factory(uri, config)
      @front = front
      @idconv = @config[:idconv]
      @safe_level = @config[:safe_level]
      EventMachine::next_tick do
        @thread = Thread.current
      end
    end

    ##
    # Start a DRb server from within an event loop.
    #
    def start_drb_server
      @thread = Thread.current
      @protocol.start_server(DRbServerProtocol) do |conn|
        conn.front = @front
        conn.load_limit = @config[:load_limit]
        conn.argc_limit = @config[:argc_limit]
        conn.idconv = @config[:idconv]
        conn.server = self
        conn.safe_level = self.safe_level
        conn.uri = @protocol.uri
        Thread.current['DRb'] = { 'client' => conn, 'server' => self }
      end
      @uri = @protocol.uri
    end

    ##
    # Stop this server.
    def stop_service
      DRb.remove_server(self)
      if Thread.current['DRb'] && Thread.current['DRb']['server'] == self
        Thread.current['DRb']['stop_service'] = true
      else
        @thread.kill
      end
      @protocol.stop_server
    end

  end

  @eventloop = nil

  ##
  # This is the 'bare bones' start_service which can be used to
  # start a DRb service from within an existing event loop.
  def start_drbserver(uri=nil, front=nil, config=nil)
    serv = DRbServer.new(uri, front, config)
    serv.start_drb_server
    DRb.regist_server(serv)
    return(serv)
  end
  module_function :start_drbserver

  ##
  # Stop all servers.
  def stop_all_servers
    @server.each do |uri,srv|
      srv.stop_service
    end
  end
  module_function :stop_all_servers

  def start_evloop
    unless EventMachine::reactor_running?
      q = Queue.new
      @eventloop = Thread.new do
        begin
          EventMachine::run do
            # Start an empty event loop.  The DRb server(s) will be started
            # by EM#next_tick calls.  Just put a dummy value into the queue
            # so that the calling thread will resume execution once this
            # event thread actually starts the loop.
            q << 1
          end
        ensure
          # close all servers if the event loop ends for whatever reason
          self.stop_all_servers
        end
      end
      q.shift
    end
  end
  module_function :start_evloop

  ##
  # This start_service emulates DRb#start_service.
  #
  def start_service(uri=nil, front=nil, config=nil)
    DRb.start_evloop
    queue = Queue.new
    EventMachine::next_tick do
      queue << self.start_drbserver(uri, front, config)
    end
    serv = queue.shift
    @primary_server = serv
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
    attr_accessor :uri

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
        @succ ? @df.succeed(@result) : @df.fail(@result)
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
        @uri, option = DRbTransport.uri_option(uri, DRb.config)
        @ref = DRbURIOption.new(option) unless option.nil?
      else
	@uri = uri ? uri : (DRb.uri rescue nil)
        @ref = obj ? DRb.to_id(obj) : nil
      end
    end

    ##
    # Perform an asynchronous call to the remote object.  This can only
    # be used from within the event loop.  It returns a deferrable, which
    # will succeed if the remote method called performs a normal return,
    # and callbacks attached to the deferrable will receive this return
    # value.  If the remote method raises an exception, it will fail the
    # deferrable, and the exception object will be passed to the errbacks
    # of the deferrable.
    def send_async(msg_id, *a, &b)
      df = EventMachine::DefaultDeferrable.new
      if DRb.here?(@uri)
        obj = DRb.to_obj(@ref)
        DRb.current_server.check_insecure_method(obj, msg_id)
        begin
          if obj.kind_of?(DRbEMSafe) && obj.class.deferrable_method?(msg_id)
            # If the method is a deferrable, calling the method will itself
            # return a deferrable by definition, and we should be using this
            # deferrable to determine whether the call succeeded or failed.
            df = obj.__send__(msg_id, *a, &b)
          else
            df.succeed(obj.__send__(msg_id, *a, &b))
          end
        rescue
          df.fail($!)
        end
        return(df)
      end

      @protocol ||= DRbTransport.factory(@uri, DRb.config)

      @protocol.client_connect(DRbClientProtocol) do |c|
        c.ref = self
        c.msg_id = msg_id
        c.args = a
        c.block = b
        c.df = df
        c.uri = @uri
      end
      return(df)
    end

    ##
    # Route method calls to the referenced object.  This synchronizes
    # an asynchronous call by using a Queue to synchronize the DRb
    # event thread with the calling thread, so use of this mechanism
    # to make method calls within an event loop will thus result in a
    # threading deadlock!  Use the send_async method if you want to
    # use EMDRb from within an event loop.
    def method_missing(msg_id, *a, &b)
      q = Queue.new
      EventMachine::next_tick do
        df = self.send_async(msg_id, *a, &b)
        df.callback { |data| q << [true, data] }
        df.errback { |exc| q << [false, exc] }
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
 
