#!/usr/bin/env perl
###################################################################
##  Author: David Jones, License: MIT, Published: 2010-04-28     ##
##                                                               ##
##  This script scrapes Craigslist at a user-defined interval    ##
##  for keywords and price ranges specified below, and emails    ##
##  the results to you (using gmail).                            ##
##                                                               ##
##  This script needs to be run in the specified interval        ##
##  by either a cron script (unix), or scheduled task (windows)  ##
###################################################################

# core modules
use strict;
use warnings;
use Data::Dumper;

# add-in modules - install with cpan, ppm, or perlbrew
use WWW::Mechanize;
use Web::Scraper;
use Time::Piece; # Time::Piece is core in perl 5.10, but needs installing on older versions
use Email::Send;
use Email::Send::SMTP::TLS;
use Email::Simple::Creator;


# USER-CONFIGURABLE VARIABLES
my $search_term  = ('honda' || $ARGV[0]); # enter a search term or pass one on the command line
my $city         = 'indianapolis';
my $category     = 'cto';          # cars & trucks all (by dealer or seller)
my $search_type  = '';             # only search titles (not body)
my $min          = '300';          # minimum price
my $max          = '6000';         # maximum price
my $result_limit = 10;             # max number of listings
my $time_window  = 30;             # check every X minutes
my $require_pics = 1;              # require the listing to have a photo
my $email_result = 0;
my $gmail_email  = 'your_email_address@gmail.com';
my $gmail_passwd = 'YourGmailPass';
# END USER-CONFIGURABLE VARIABLES


my $email_body = ''; # empty string to concat results onto before emailing

# $spider is the Mechanize object for web crawling
my $spider = WWW::Mechanize->new( autocheck => 1 );

# go to the craigslist page for the category you want
$spider->get('http://'.$city.'.craigslist.org/'.$category);

# fill in the search form with the below settings
$spider->submit_form(
  form_number => 1,
  fields => {
    'query'           => $search_term,
    'catAbbreviation' => $category,     # category abbreviation
    'minAsk'          => $min,          # minimum price
    'maxAsk'          => $max,          # maximum price
    'srchType'        => '',            # only search titles (not body)
    'hasPic'          => $require_pics, # photo required?
  }
);

# get all links on the resulting page and stuff into @links array
my @links = $spider->find_all_links( url_regex => qr/\d{10}\.html/i );

my $result_count = 1; # counter for loop below

# loop over all the links
for my $link (@links) {
  my $url = $link->[0];

  # visit the listing linked
  $spider->get( $url );

  # save a copy of the linked source
  my $body = $spider->content();

  # search the source for the date and listing body
  &search($spider, $body, $url);

  # check to see if we hit the limit_result defined above
  if ($result_count >= $result_limit) {
    &finish(); # if so, email & exit
  } else {
    $result_count++;
  }
}


### SUBROUTINES ###

sub finish {
  # uncomment the below line to debug to screen
  if ( $email_result ) {
    &send_email($email_body);
  } else {
    print Dumper $email_body;
  }
  exit();
}

sub search {
  my $spider = shift;
  my $body   = shift;
  my $link   = shift;
  my $date;

  # define rule for scraper
  my $posting = scraper {
    process "div#userbody", text => "TEXT";
  };

  # scrape the page, whatever matches the rule goes into $result
  my $result = $posting->scrape($body);

  # scrape the page against a regex to get the date
  if ($body =~ qr[Date: (\d{4}-\d{2}-\d{2},.*?)<br>]i) {
    $date = $1; # capture result of above regex
  }

  # if scrape is successful, it will have $result & $date
  if ($result && $date) {
    # check if date is newer than cycle
    if (&post_is_new($date)){
      # add this listing to the email
      &add_posting($link, $date, $result->{'text'});
    }
  }
}

sub add_posting {
  my $link    = shift;
  my $date    = shift;
  my $posting = shift;
  $email_body .= "\n\n$date\n$link\n$posting";
}

sub post_is_new {
  my $date = shift;
  # reverse engineer the time given to a Time::Piece localtime object
  my $list_time = Time::Piece->strptime($date, "%Y-%m-%d, %k:%M%p EDT");
  my $now = localtime;
  my $time_ago = ($now - ($time_window * 60));
  # if listing is newer than time_window in minutes
  if (
    # the date is the same
    ($list_time->ymd('') eq $time_ago->ymd('')) &&
    # and the post time is less than the time_ago of last check
    ($list_time->hms('') > $time_ago->hms(''))
  ) { return 1; }
  else { return 0; }
}

# GMAIL
sub send_email {
  my $message = shift;
  my $mailer = Email::Send->new({
    mailer => 'SMTP::TLS',
    mailer_args => [
      Host     => 'smtp.gmail.com',
      Port     => 587,
      User     => $gmail_email,
      Password => $gmail_passwd,
      Hello    => 'gmail.com',
    ]
  });

  my $email = Email::Simple->create(
    header => [
      From    => $gmail_email,
      To      => $gmail_email,
      Subject => 'New Craigslist postings',
    ],
    body => $message,
  );

  eval { $mailer->send($email) };
  die "Error sending email: $@" if $@;
  return(1);
}
