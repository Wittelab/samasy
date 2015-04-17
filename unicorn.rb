@dir = File.expand_path(File.dirname(__FILE__))

# Number of processes
# worker_processes 4
worker_processes 2
# Time-out
timeout 60

# Set the working application directory
working_directory @dir

# Unicorn socket
# listen "/tmp/unicorn.[app name].sock"
listen "/tmp/unicorn.platemaker.sock", :backlog => 64

# Unicorn PID file location
pid "#{@dir}/tmp/pids/unicorn.pid"

# Path to logs
stderr_path "#{@dir}/logs/unicorn.stderr.log"
stdout_path "#{@dir}/logs/unicorn.stdout.log"