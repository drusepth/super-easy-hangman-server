require 'socket' # TCPServer, TCPSocket
require 'state_machines'

server = TCPServer.new('localhost', 9001)

def debug message, channel=:debug
  STDERR.puts "#{channel}: #{message}"
end

class Game
  attr_accessor :socket, :lives
  
  state_machine :state, initial: :initializing do
    event :show_start_menu do
      transition :ready => :menu
    end
    
    event :start_new_game do
      transition menu: :active_game
    end
    
    event :play_game do
      transition :active_game => :active_game
    end
    
    event :game_over do
      transition :active_game => :game_over
    end

    event :reset do
      transition :game_over => :ready
    end
    
    def initialize
      super()
    end
  end

  #todo allow writing to multiple sockets  
  def attach_socket output_socket
    @socket = output_socket
  end
  
  def show_start_menu
    socket.puts [ #todo center text in bounding box
      'Welcome to the Super Easy Hangman Telnet Server (SETHS)',
      'Would you like to play a game?'
    ].join "\r\n"

    super
  end
end

#todo allow more than 1 connection at a time
debug "Server is now accepting connections.", :success
socket = server.accept

#todo should probably throw this loop in a thread
debug "A client has connected!", :success
game = Game.new
game.attach_socket socket
game.state = :ready
loop do
  socket.puts game.state
  game.show_start_menu! if game.can_show_start_menu?
  
  input = socket.gets #blocking #todo allow for multi-line commands
  debug input
  
  game.start_new_game if game.can_start_new_game? && input.chomp == 'y'
  game.play_game      if game.can_play_game?
  game.game_over      if game.can_game_over?
  game.reset          if game.can_reset? && input.chomp == 'y'
end

socket.close
