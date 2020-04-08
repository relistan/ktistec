require "../framework"

class WellKnownController
  include Balloon::Controller

  get "/.well-known/webfinger" do |env|
    domain = (host =~ /\/\/([^\/]+)$/) && $1

    server_error unless $1
    bad_request unless resource = env.params.query["resource"]?
    bad_request unless resource =~ /^acct:([^@]+)@(#{domain})$/

    actor = Actor.find(username: $1)

    message = {
      subject: resource,
      aliases: [
        "#{host}/actors/#{$1}"
      ],
      links: [{
                rel: "self",
                href: "#{host}/actors/#{$1}",
                type: "application/activity+json"
              }, {
                rel: "http://webfinger.net/rel/profile-page",
                href: "#{host}/actors/#{$1}",
                type: "text/html"
              }]
    }
    env.response.content_type = "application/jrd+json"
    message.to_json
  rescue ex: DB::Error
    not_found if ex.message == "no rows"
    raise ex
  end
end