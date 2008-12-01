require 'rubygems'
require 'feed_tools'
require 'sinatra'
require 'rest_client'
require 'json'

# New action creates the import form with the following fields:
# * Disqus API Key (http://disqus.com/api/get_my_key/)
# * Forum Short Name (from Disqus)
# * Existing Blog Comment RSS URL (The url for the comments rss feed of the blog we are importing into Disqus)
# * The blog article RSS url of the blog that will be using Disqus (We need this to tie the blog url with Disqus comments)
# * Number of comments to import (this is used for testing to verify a small subset of comments look good in Disqus after importing)
get '/new' do
  body <<-eos
    <h3>Import comments into Disqus</h3>
    <form action='/create' method='post'>
    <label for='api_key'>Disqus API Key</label><br />
    <input type='text' name='api_key' /><br />
    <label for='short_name'>Forum Short Name</label><br />
    <input type='text' name='short_name' /><br />
    <label for='comment_rss_url'>Existing Blog Comment RSS URL</label><br />
    <input type='text' name='comment_rss_url' /><br />
    <label for='blog_rss_url'>New Blog Article RSS URL</label><br />
    <input type='text' name='blog_rss_url' /><br />
    <label for='number_of_comments'>Number Of Commments To Import (Leave blank to import all)</label><br />
    <input type='text' name='number_of_comments' /><br /><br />
    <input type='submit' name='submit' value='Import Into Disqus' />
    </form>
    eos
end

post '/create' do
  disqus_url = 'http://disqus.com/api'
  user_api_key, old_blog_comment_rss, forum_shortname, current_blog_rss = params[:api_key], params[:comment_rss_url], params[:short_name], params[:blog_rss_url]
  number_of_comments = params[:number_of_comments]
  
  resource = RestClient::Resource.new disqus_url
  forums = JSON.parse(resource['/get_forum_list?user_api_key='+user_api_key].get)
  forum_id = forums["message"].select {|forum| forum["shortname"]==forum_shortname}[0]["id"]
  forum_api_key = JSON.parse(resource['/get_forum_api_key?user_api_key='+user_api_key+'&forum_id='+forum_id].get)["message"]
  
  # Get all of the comments from the old blog site
  comments = FeedTools::Feed.open(old_blog_comment_rss)
  
  # Get all of the articles from the current blog site
  articles = FeedTools::Feed.open(current_blog_rss)
  
  comment_text = ""
  failed_imports = ""
  successful_imports = ""
  
  comments_to_import = number_of_comments.blank? ? comments.items : comments.items[0..number_of_comments.to_i-1]
  
  comments_to_import.each do |comment|
    comment_article_title = comment.title.sub(/^Comment on /, "").sub(/by.*$/, "").strip
    
    # Get the blog article for the current comment thread
    article = articles.items.select {|a| a.title.downcase == comment_article_title.downcase}[0]

    if article
      article_url = article.link  

      thread = JSON.parse(resource['/get_thread_by_url?forum_api_key='+forum_api_key+'&url='+article_url].get)["message"]

      # If a Disqus thread is not found with the current url, create a new thread and add the url.
      if thread.nil?  
        thread = JSON.parse(resource['/thread_by_identifier'].post(:forum_api_key => forum_api_key, :identifier => comment.title, :title => comment.title))["message"]["thread"]
      
        # Update the Disqus thread with the current article url
        resource['/update_thread'].post(:forum_api_key => forum_api_key, :thread_id => thread["id"], :url => article_url) 
      end

      # Import posts here
      begin
        post = resource['/create_post'].post(:forum_api_key => forum_api_key, :thread_id => thread["id"], :message => comment.description, :author_name => comment.author.name, :author_email => comment.author.email, :created_at => comment.time.strftime("%Y-%m-%dT%H:%M"))
      rescue
        failed_imports += "<li>"+comment.description[0..100]+" <a href=#{article_url}>link</a>" + "</li>"
      else
        successful_imports += "<li>"+comment.description[0..100]+" <a href=#{article_url}>link</a>" + "</li>"
      end
    end
  end
  
  failed_import_message = "<h2>The following comments failed to import</h2><ul>" + failed_imports + "</ul>"
  successful_import_message = "<h2>The following comments were imported successfully</h2><ul>" + successful_imports + "</ul>"
  
  output_message =  successful_import_message + "<br />"
  output_message += failed_import_message unless failed_imports.blank?
  
  body output_message
end
