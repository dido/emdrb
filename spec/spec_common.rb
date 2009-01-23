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
describe "DRb basics", :shared => true do
  it "should be able to perform simple synchronous method calls" do
    @obj.identity(1).should == 1
    @obj.addtwo(1, 2).should == 3
  end

  it "should be able to perform synchronous method calls with a block" do
    val = 1
    @obj.blockyield(1,2,3,4,5,6,7) { |x| val *= x }
    val.should == 5040
  end

end
