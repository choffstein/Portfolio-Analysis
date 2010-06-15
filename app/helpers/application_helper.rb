# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  def r_instance
    r = RSRuby.instance
    r.library("BLCOP")
    r.library("fPortfolio")

    return r
  end
end
