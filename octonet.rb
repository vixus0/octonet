#!/usr/bin/env ruby

require 'cgi'
require 'json'
require 'logger'
require 'octonet/client'
require 'octonet/graph'
require 'securerandom'
require 'sinatra'

LOG = Logger.new(STDERR)
LOG.level = Logger::INFO

enable :sessions

configure do
  set hostname: ENV.fetch('HOSTNAME')
  set oauth_client_id: ENV.fetch('OAUTH_CLIENT_ID')
  set oauth_client_secret: ENV.fetch('OAUTH_CLIENT_SECRET')
  set oauth_url: ENV.fetch('OAUTH_URL')
  set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
  set :sessions, expire_after: 600
  set :bind, '0.0.0.0'
  set :port, ENV.fetch('PORT', 4567)
end

set(:auth) do |_|
  condition do
    if session[:token].nil?
      redirect '/oauth', 303
    end
  end
end

get '/', :auth => true do
  client = Octonet::Client.new(session[:token])
  client.query(Octonet::Client::TestQuery)
  erb :index
rescue Octonet::Client::ForbiddenError => e
  LOG.info("User is forbidden")
  redirect "https://github.com/settings/connections/applications/#{settings.oauth_client_id}", 303
rescue Octonet::Client::UnauthorizedError => e
  LOG.info("User is unauthorised")
  session.delete(:token)
  redirect '/', 303
end

get '/graph.json' do
  content_type :json
  expires 600, :private
  LOG.info("Creating graph ...")
  @graph = Octonet::Graph.new(session[:token])
  @graph.data.to_json
rescue Octonet::Client::ForbiddenError => e
  halt 403, e.message
rescue Octonet::Client::TimeoutError => e
  halt 408, e.message
end

get '/oauth' do
  state = SecureRandom.hex(10)
  session[:state] = state
  redirect "#{settings.oauth_url}/authorize?client_id=#{settings.oauth_client_id}&redirect_uri=#{settings.hostname}/oauth/callback&allow_signup=false&state=#{state}&scope=read:org"
end

get '/oauth/callback' do
  if params['error']
    halt 500, "OAuth error: [#{params['error']}]: #{params['error_description']}"
  end

  code = params['code']
  state = params['state']

  if state != session[:state]
    LOG.warn("state mismatch: #{state.inspect} != #{session[:state].inspect}")
    halt 403
  end

  uri = URI("#{settings.oauth_url}/access_token")
  res = Net::HTTP.post_form(
    uri,
    'client_id' => settings.oauth_client_id,
    'client_secret' => settings.oauth_client_secret,
    'code' => code,
    'redirect_uri' => "#{settings.hostname}/oauth/callback",
    'state' => state
  )

  params = CGI.parse(res.body)
  token = params['access_token'][0]

  if token.nil?
    LOG.error("token was nil! params: #{params.inspect}")
    halt 500
  end

  session[:token] = token
  redirect '/', 303
end
