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

  def teams_query(vars = {})
    result = Github::Client.query(Github::TeamsQuery, variables: vars.merge({ 'org': ORG }))

    if result.data.nil?
      LOG.error("no result data")
      LOG.error("result: #{result.inspect}")
      abort
    end

    teams = result.data&.organization&.teams
    
    unless teams.nil?
      LOG.info("limit: #{result.data.rate_limit.remaining}/#{result.data.rate_limit.limit} remaining")
      LOG.info("nteams: #{teams.nodes.size}")

      teams.nodes.each do |team|
        LOG.info("team: #{team.slug}")
        @nodes.add({ 'id': team.slug, 'group': 1 })

        team.members.edges.each do |edge|
          member = edge.node
          LOG.info("  member: #{member.login} '#{member.name}' #{edge.role}")
          @nodes.add({ 'id': member.login, 'data': {'name': member.name}, 'group': 2 })
          @links.push({ 'source': member.login, 'target': team.slug, 'label': edge.role })
        end

        team.repositories.edges.each do |edge|
          repo = edge.node
          LOG.info("  repo: #{repo.name} #{edge.permission}")
          @nodes.add({ 'id': repo.name, 'group': 3 })
          @links.push({ 'source': repo.name, 'target': team.slug, 'label': edge.permission })
        end

        if team.repositories.page_info.has_next_page
          repos_query({ 'teamSlug': team.slug, 'repoCursor': team.repositories.page_info.end_cursor })
        end
      end

      if teams.page_info.has_next_page
        teams_query({ 'teamCursor': teams.page_info.end_cursor })
      end
    end
  end

  def repos_query(vars = {})
    result = Github::Client.query(Github::ReposQuery, variables: vars.merge({ 'org': ORG }))
    repos = result.data&.organization&.team&.repositories
    
    if repos.nil?
      LOG.error("no such team: #{vars['teamSlug']}")
      abort
    end
    
    repositories.edges.each do |edge|
      repo = edge.node
      LOG.info("  repo: #{repo.name} #{edge.permission}")
      @nodes.add({ 'id': repo.name, 'group': 3 })
      @links.push({ 'source': repo.name, 'target': vars['teamSlug'], 'label': edge.permission })
    end

    if repositories.page_info.has_next_page
      repos_query({ 'teamSlug': vars['teamSlug'], 'repoCursor': repositories.page_info.end_cursor })
    end
  end
end

graph = Graph.new
puts JSON.dump({
  'nodes': graph.nodes.to_a,
  'links': graph.links
})
