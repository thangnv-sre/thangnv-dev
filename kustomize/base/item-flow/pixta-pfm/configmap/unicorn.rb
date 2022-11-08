worker_processes Integer(ENV['WEB_CONCURRENCY'] || 5)
timeout 600
preload_app true

before_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn master intercepting TERM and sending myself QUIT instead'
    Process.kill 'QUIT', Process.pid
  end
end

after_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn worker intercepting TERM and doing nothing. Wait for master to send QUIT'
  end
end

working_directory "./"

listen "/var/run/sock/unicorn.sock", :backlog => 64
pid "./tmp/pids/unicorn.pid"

stderr_path "./log/unicorn_error.log"
stdout_path "./log/unicorn.log"
