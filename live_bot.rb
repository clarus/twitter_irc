# IRC bot to notify new tweets
require "rubygems"
require "logger"
require "yaml"
require "socket"
require "twitter"

$log = Logger.new("live_bot.log")
$log.level = Logger::INFO
puts "Log added in \"live_bot.log\""
$stdout.flush

# IRC bot doing writing only
class IrcBot
  def initialize(config)
    @server = config["server"]
    @port = config["port"]
    @channel = config["channel"]
    @password = config["password"]
    @nick = config["nick"]
    @real_name = config["real_name"]
    
    connect
  end
  
  # send a text message to the chan
  def message(msg)
    puts("PRIVMSG #{@channel} :#{msg}")
    $log.info("said on IRC : #{msg}")
  end

private
  def puts(msg)
    @socket.puts(msg)
    $log.debug("IRC >> #{msg.chomp}")
  end
  
  def gets
    msg = @socket.gets
    $log.debug("IRC << #{msg.chomp}")
    return msg
  end
  
  def connect
    $log.info("connecting to IRC")
    @socket = TCPSocket.new(@server, @port)
    puts("NICK #{@nick}")
    puts("USER #{@nick} 0 * : #{@real_name}")
    
    # we wait to be connected to be able to join
    while line = gets
      if line =~ /^:\S+ 00[1..4]/
        $log.info("connected to IRC as #{@nick}")
        puts("JOIN #{@channel} #{@password}")
        message("coucou")
        break
      end
    end
    
    answer_pings
  end
  
  # independent thread to answer to server pings
  def answer_pings
    Thread.new do
      while line = gets
        if line =~ /^(:\S+ )?PING (.*)/
          $log.debug("<< #{line.chomp}")
          puts("PONG #{$2}")
        end
      end
    end
  end
end

# A new tweet fetcher
class TwitterReader
  def initialize(login)
    # try the login
    @login = login
    begin Twitter.user(@login)
    rescue Twitter::NotFound => e
      $log.error("#{@login} not found on Twitter")
      raise e
    end
    
    # compute the last message id
    @last_id = 0
    handle_twitter_exceptions do
      Twitter::Search.new.from(@login).each do |tweet|
        @last_id = tweet.id if tweet.id > @last_id
      end
    end
    
    $log.info("connected to Twitter")
  end
  
  # get new tweets since the last call
  def new_tweets
    handle_twitter_exceptions do
      Twitter::Search.new.from(@login).since(@last_id).collect do |tweet|
        $log.info("new tweet : #{tweet.text}")
        @last_id = tweet.id if tweet.id > @last_id
        tweet.text
      end
    end
  end

private
  # handle excpetions from Twitter servers
  def handle_twitter_exceptions(&p)
    begin
      p.call
    rescue Twitter::Unavailable
      $log.error("Twitter unavailable")
      sleep(2)
      handle_twitter_exceptions(&p)
    rescue Twitter::TwitterError => e
      $log.error("Twitter exception")
      raise e
    end
  end
end

config = YAML::load(ARGF.read)
bot = IrcBot.new(config["irc"])
twitter = TwitterReader.new(config["twitter"])

# main loop
loop do
  # refresh each minute
  sleep(60)
  twitter.new_tweets.each do |tweet|
    bot.message("sur http://twitter.com/#{config["twitter"]} :")
    bot.message("« #{tweet} »")
  end
end
