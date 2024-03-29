require 'logger'
require 'octonet/client'

module Octonet
  class Graph
    attr_reader :links, :teams, :members, :repos

    LOG = Logger.new(STDERR)
    LOG.level = Logger::INFO

    def initialize(token)
      @client = Octonet::Client.new(token)
      @teams = {}
      @members = {}
      @repos = {}
      @links = []
      teams_query
      calc_sizes
    end

    def data
      {
        'teams': @teams.values,
        'members': @members.values,
        'repos': @repos.values,
        'links': @links
      }
    end

  private

    def teams_query(vars = {})
      result = @client.query(Octonet::Client::TeamsQuery, vars)
      teams = result.data&.organization&.teams

      LOG.debug("result: #{result.inspect}")
      LOG.debug("result.data: #{result.data.errors.inspect}")

      unless teams.nil?
        LOG.debug("limit: #{result.data.rate_limit.remaining}/#{result.data.rate_limit.limit} remaining")
        LOG.debug("nteams: #{teams.nodes.size}")

        teams.nodes.each do |team|
          LOG.debug("team: #{team.slug}")

          @teams[team.slug] = {
            'id' => "team--#{team.slug}",
            'type' => 'team',
            'label' => team.slug,
            'name' => team.name,
            'size' => 0,
          }

          team.members.edges.each do |edge|
            member = edge.node
            LOG.debug("  member: #{member.login} '#{member.name}' #{edge.role}")

            @members[member.login] = {
              'id' => "user--#{member.login}",
              'type' => 'user',
              'label' => member.login,
              'name' => member.name,
              'avatar' => member.avatar_url,
              'size' => 0,
            }

            @links.push({ 'source' => "user--#{member.login}", 'target' => "team--#{team.slug}", 'label' => edge.role })
          end

          team.repositories.edges.each do |edge|
            unless edge.nil? # private repos are nil I think
              repo = edge.node
              LOG.debug("  repo: #{repo.name} #{edge.permission}")

              @repos[repo.name] = {
                'id' => "repo--#{repo.name}",
                'type' => 'repo',
                'label' => repo.name,
                'size' => 0,
              }

              @links.push({ 'source' => "team--#{team.slug}", 'target' => "repo--#{repo.name}", 'label' => edge.permission })
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
      result = @client.query(Octonet::Client::ReposQuery, vars)
      repos = result.data&.organization&.team&.repositories

      if repos.nil?
        LOG.debug("repos nil for team: #{vars['teamSlug']}")
        return
      end

      repos.edges.each do |edge|
        unless edge.nil?
          repo = edge.node
          LOG.debug("  repo: #{repo.name} #{edge.permission}")

          @repos[repo.name] = {
            'id' => "repo--#{repo.name}",
            'type' => 'repo',
            'label' => repo.name,
            'size' => 0,
          }

          @links.push({ 'source' => "team--#{vars[:teamSlug]}", 'target' => "repo--#{repo.name}", 'label' => edge.permission })
        end
      end

      if repos.page_info.has_next_page
        repos_query({ teamSlug: vars[:teamSlug], repoCursor: repos.page_info.end_cursor })
      end
    end

    def calc_sizes
      @teams.keys.each { |team| @teams[team]['size'] = @links.map { |link| link['source'] }.grep("team--#{team}").size }
      @members.keys.each { |member| @members[member]['size'] = @links.map { |link| link['source'] }.grep("user--#{member}").size }
    end
  end
end
