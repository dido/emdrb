# -*- coding: utf-8; mode: Ruby -*-
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
begin
  require 'bones'
  require 'bones/plugins/test'
  require 'bones/plugins/rubyforge'
rescue LoadError
  abort '### Please install the "bones" gem ###'
end

task :default => 'test:run'

ensure_in_path 'lib'
require 'emdrb/version'

Bones {
  name 'emdrb'
  authors 'dido@imperium.ph'
  email 'dido@imperium.ph'
  url 'http://emdrb.rubyforge.org'
  version EMDRb::VERSION
  depend_on "eventmachine"
}

# EOF
