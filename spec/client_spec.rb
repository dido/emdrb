#
# $Id$
#
require File.join(File.dirname(__FILE__), %w[spec_helper])
require 'drb'
require 'thread'

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

describe EMDRb, "Client" do
  before(:all) do
    DRb.start_service("druby://:12345", TestServer.new)
    @obj = DRb::DRbObject.new(nil, "druby://localhost:12345")
  end

  it "should be able to perform simple synchronous method calls" do
    @obj.identity(1).should == 1
    @obj.addtwo(1, 2).should == 3
  end

  it "should be able to perform synchronous method calls with a block" do
    val = 1
    @obj.blockyield(1,2,3,4,5,6,7) { |x| val *= x }
    val.should == 5040
  end

  it "should be able to perform asynchronous method calls" do
    q = Queue.new
    EventMachine::next_tick do
      @obj.send_async(:identity, 1).callback do |data|
        data[0].should be_true
        data[1].should == 1
        q << data
      end
    end
    q.shift
  end

  it "should be able to perform asynchronous method calls with a passed block" do
    EventMachine::next_tick do
      q = Queue.new
      df = @obj.send_async(:blockyield, 1,2,3,4,5,6,7) { |x| val *= x; val }
      df.callback do |data|
        data[0].should be_true
        q << data
      end
      q.shift
      val.should == 5040
    end
  end

end
