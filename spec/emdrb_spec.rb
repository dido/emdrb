#
# $Id$
#
require File.join(File.dirname(__FILE__), %w[spec_helper])
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

describe EMDRb do
  before(:each) do
    EMDRb.start_service("druby://:12345", TestServer.new)
  end

  it "should handle basic method calls from the standard DRb client" do
    o = DRbObject.new_with_uri("druby://localhost:12345")
    DRb.start_service
    o.identity(1).should == 1
    o.addtwo(1, 2).should == 3
  end
end
