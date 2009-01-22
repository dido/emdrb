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

describe "EMDRbServer" do
  before(:all) do
    EMDRb.start_service("druby://:12345", TestServer.new)
    DRb.start_service
    @obj = DRbObject.new_with_uri("druby://localhost:12345")
  end

  it "should handle basic method calls from the standard DRb client" do
    @obj.identity(1).should == 1
    @obj.addtwo(1, 2).should == 3
  end

  it "should raise an error if insufficient arguments are provided to a remote method call" do
    lambda { @obj.addtwo(1) }.should raise_error(ArgumentError)
  end

  it "should work with variadic methods" do
    @obj.sum(1,2,3,4,5).should == 15
  end

  it "should allow blocks to be passed" do
    val = 1
    @obj.blockyield(1,2,3,4,5,6,7) { |x| val *= x }
    val.should == 5040
  end

  after(:all) do
    EMDRb.thread.kill
  end

end
