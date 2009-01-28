#
# Author:: Rafael R. Sevilla (mailto:dido@imperium.ph)
# Copyright:: Copyright © 2008, 2009 Rafael R. Sevilla
# Homepage:: http://emdrb.rubyforge.org/
# License:: GNU General Public License / Ruby License
#
# $Id: emdrb.rb 72 2009-01-28 09:53:08Z dido $
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
require 'drb/unix'

module DRb

  ##
  # Unix domain socket transport
  class DRbUNIXSocket < DRbTCPSocket
    public

    def initialize(uri, config={})
      @uri = (uri.nil?) ? 'drbunix:' : uri
      @filename, @option = self.class.parse_uri(@uri)
      @filename.untaint
      @port.untaint
      @config = config
      @acl = nil
    end

    def start_server(prot)
      lock = nil
      if @filename.nil?
        tmpdir = Dir::tmpdir
        n = 0
        while true
          begin
            tmpname = sprintf('%s/druby%d.%d', tmpdir, $$, n)
            lock = tmpname + '.lock'
            unless File.exist?(tmpname) or File.exist?(lock)
              Dir.mkdir(lock)
              @filename = tmpname
              break
            end
          rescue
            raise "cannot generate tempfile `%s'" % tmpname if n >= Max_try
            #sleep(1)
          end
          n += 1
        end
      end

      EventMachine::start_unix_domain_server(@filename, prot) do |conn|
        if block_given?
          yield conn
        end
      end

      if lock
        Dir.rmdir(lock)
      end
    end

    def client_connect(prot)
      EventMachine.connect_unix_domain(@filename, prot) do |c|
        if block_given?
          yield c
        end
      end
    end
  end

  DRbTransport.add_transport(DRbUNIXSocket)
end
