#
# Author:: Rafael R. Sevilla (mailto:dido@imperium.ph)
# Copyright:: Copyright (c) 2008 Rafael R. Sevilla
# Homepage:: http://emdrb.rubyforge.org/
# License:: GNU Lesser General Public License / Ruby License
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
# EMDRb version code
#
module EMDRb
  module Version

    MAJOR = 0
    MINOR = 3
    TINY = 1

    # The version of EMDRb in use.
    STRING = [ MAJOR, MINOR, TINY ].join(".")
  end  
end
