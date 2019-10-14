require 'graphql/client'
require 'graphql/client/http'

module Octonet
  API_URL = ENV.fetch('GITHUB_GRAPHQL_API_URL', 'https://api.github.com/graphql')
  ORG = ENV.fetch('GITHUB_ORG')

  class Client
    attr_reader :teams_query, :repos_query

    LOG = Logger.new(STDERR)
    LOG.level = Logger::INFO

    class ForbiddenError < StandardError
    end

    class UnauthorizedError < StandardError
    end

    class TimeoutError < StandardError
    end

    HTTP = GraphQL::Client::HTTP.new(API_URL) do
      def headers(context)
        if context[:token]
          { 'User-Agent': 'octonet', 'Authorization': "bearer #{context[:token]}" }
        else
          {}
        end
      end
    end

    Schema = GraphQL::Client.load_schema('github_schema.json')
    Client = GraphQL::Client.new(schema: Schema, execute: HTTP)

    TestQuery = Client.parse <<~QUERY
      query($org: String!) {
        rateLimit{
          cost
          limit
          nodeCount
          remaining
          resetAt
        }
        organization(login: $org) {
          teams(first: 1) {
            pageInfo { endCursor }
          }
        }
      }
    QUERY

    TeamsQuery = Client.parse <<~QUERY
      query($org: String!, $teamCursor: String){
        rateLimit{
          cost
          limit
          nodeCount
          remaining
          resetAt
        }
        organization(login: $org) {
          teams(first: 100, after: $teamCursor) {
            pageInfo {
              endCursor
              hasNextPage
            }
            nodes {
              slug
              name
              parentTeam {name}
              members {
                edges {
                  node {name, login, avatarUrl(size: 128)}
                  role
                }
              }
              repositories(first: 100) {
                pageInfo {
                  endCursor
                  hasNextPage
                }
                edges {
                  node {
                    name
                    parent {name}
                  }
                  permission
                }
              }
            }
          }
        }
      }
    QUERY

    ReposQuery = Client.parse <<~QUERY
      query($org: String!, $teamSlug: String!, $repoCursor: String){
        rateLimit{
          cost
          limit
          nodeCount
          remaining
          resetAt
        }
        organization(login: $org) {
          team(slug: $teamSlug) {
            repositories(first: 100, after: $repoCursor) {
              pageInfo {
                endCursor
                hasNextPage
              }
              edges {
                node {
                  name
                  parent {name}
                }
                permission
              }
            }
          }
        }
      }
    QUERY

    def initialize(token)
      @token = token
    end

    def query(q, vars = {}, max_retries = 10)
      tries = 0

      until tries == max_retries
        result = Client.query(q, variables: vars.merge({ 'org': ORG }), context: { token: @token })

        unless result.errors.nil?
          message = result.errors.messages.to_h.dig('data', 0)

          case message
          when '401 Unauthorized'
            raise UnauthorizedError, "not authorised"
          when '502 Bad Gateway'
            LOG.warn("Got bad gateway, retrying (#{tries}/#{max_retries})")
            tries += 1
            sleep(2)
            next
          end
        end

        if result.data.nil?
          LOG.error("data was nil. result: #{result.inspect}")
          raise StandardError, "data was nil"
        end

        unless result.data.errors.nil?
          details = result.data.errors.details.to_h

          if details.dig('organization', 0, 'type') == 'FORBIDDEN'
            message = details.dig('organization', 0, 'message')
            LOG.error("Access to org #{ORG} is forbidden. Message: #{message}")
            raise ForbiddenError, message
          end
        end

        return result
      end

      raise TimeoutError, "request timed out"
    end
  end
end
