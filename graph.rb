#!/usr/bin/env ruby

require 'set'
require 'json'
require 'logger'

require 'graphql/client'
require 'graphql/client/http'

LOG = Logger.new(STDERR)
LOG.level = Logger::INFO

ORG = ENV.fetch('GITHUB_ORG')

module Github
  HTTP = GraphQL::Client::HTTP.new("https://api.github.com/graphql") do
    def headers(context)
      {
        'User-Agent': 'octonet',
        'Authorization': "bearer #{ENV.fetch('GITHUB_TOKEN')}"
      }
    end
  end  

  unless File.exist?('.github.json')
    GraphQL::Client.dump_schema(HTTP, '.github.json')
  end

  Schema = GraphQL::Client.load_schema('.github.json')
  Client = GraphQL::Client.new(schema: Schema, execute: HTTP)

  TeamsQuery = Client.parse(File.read('teams.query'))
  ReposQuery = Client.parse(File.read('repos.query'))
end

class Graph
  attr_reader :nodes, :links

  def initialize
    @nodes = Set.new
    @links = []
    teams_query
  end

private

  def query(q, vars, max_retries = 10)
    tries = 0

    until tries == max_retries
      result = Github::Client.query(q, variables: vars.merge({ 'org': ORG }))

      if result.data.nil?
        if result.errors.messages['data'][0].downcase.include?('bad gateway')
          tries = tries + 1
          LOG.warn("Got 502 Bad Gateway, retrying")
          sleep(1)
          next
        end
        break
      end

      return result
    end

    LOG.error("no result data")
    LOG.error("result: #{result.inspect}")
    abort
  end

  def teams_query(vars = {})
    result = query(Github::TeamsQuery, vars)
    teams = result.data&.organization&.teams
    
    unless teams.nil?
      LOG.info("limit: #{result.data.rate_limit.remaining}/#{result.data.rate_limit.limit} remaining")
      LOG.info("nteams: #{teams.nodes.size}")

      teams.nodes.each do |team|
        LOG.info("team: #{team.slug}")
        @nodes.add({ 'id' => "team:#{team.slug}", 'label' => team.slug, 'name' => team.name, 'group' => 1 })

        team.members.edges.each do |edge|
          member = edge.node
          LOG.info("  member: #{member.login} '#{member.name}' #{edge.role}")
          @nodes.add({ 'id' => "user:#{member.login}", 'label' => member.login, 'name' => member.name, 'group' => 2 })
          @links.push({ 'source' => "user:#{member.login}", 'target' => "team:#{team.slug}", 'label' => edge.role })
        end

        team.repositories.edges.each do |edge|
          unless edge.nil? # private repos are nil I think
            repo = edge.node
            LOG.info("  repo: #{repo.name} #{edge.permission}")
            @nodes.add({ 'id' => "repo:#{repo.name}", 'label' => repo.name, 'group' => 3 })
            @links.push({ 'source' => "team:#{team.slug}", 'target' => "repo:#{repo.name}", 'label' => edge.permission })
          end
        end

        if team.repositories.page_info.has_next_page
          repos_query({ teamSlug: team.slug, repoCursor: team.repositories.page_info.end_cursor })
        end
      end

      if teams.page_info.has_next_page
        teams_query({ teamCursor: teams.page_info.end_cursor })
      end
    end
  end

  def repos_query(vars = {})
    result = query(Github::ReposQuery, vars)
    repos = result.data&.organization&.team&.repositories
    
    if repos.nil?
      LOG.info("repos nil for team: #{vars['teamSlug']}")
      return
    end
    
    repos.edges.each do |edge|
      unless edge.nil?
        repo = edge.node
        LOG.info("  repo: #{repo.name} #{edge.permission}")
        @nodes.add({ 'id' => "repo:#{repo.name}", 'label' => repo.name, 'group' => 3 })
        @links.push({ 'source' => "team:#{vars[:teamSlug]}", 'target' => "repo:#{repo.name}", 'label' => edge.permission })
      end
    end

    if repos.page_info.has_next_page
      repos_query({ teamSlug: vars[:teamSlug], repoCursor: repos.page_info.end_cursor })
    end
  end
end

graph = Graph.new
puts JSON.dump({
  'nodes': graph.nodes.to_a,
  'links': graph.links
})
