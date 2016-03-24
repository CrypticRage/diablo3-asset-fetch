#!/usr/bin/perl
use strict;
use warnings;
use feature qw(say);

use LWP::Simple;
use HTML::Tree;

# URLs
my $base_url = "http://us.battle.net";
my $item_list_url = $base_url . "/d3/en/item/";

# REGEXs
my $item_link_pattern = qr!item/(([a-z]|[0-9]|-)+)/?!;
my $recipe_link_pattern = qr!artisan/(.*)/recipe/(([a-z]|[0-9]|-)+)/?!;
my $img_style_pattern = qr/url\(((.*)\/(.*).png)\)/;
my $img_filename_pattern = qr!^(.+)/([^/]+)$!;

# SUB unique - return an array with only the unique elements of a given array
sub unique
{
    my %seen = ();
    my @r = ();
    foreach my $a (@_)
    {
        unless ($seen{$a})
        {
            push @r, $a;
            $seen{$a} = 1;
        }
    }
    return @r;
}

# SUB parse_img_link - parse the background image link from a given tag
sub parse_img_link
{
    # say "parsing image link...";
    my $r = ();
    my $item_img_tag = $_->look_down(
        "class" => qr/icon-item/,
        "style" => qr/background-image/
    );
    
    unless (!$item_img_tag)
    {
        if($item_img_tag->attr("style") =~ $img_style_pattern)
        {
            $r = $1;
        }
    }
    
    return $r;
}

# SUB parse_item - parse item links and image info from a given item tag
sub parse_item
{
    # say "parsing item...";
    my %r = ();
    my $item_name = ();
    my $item_link = ();
    my $item_link_tag = $_->look_down(
        "_tag" => "a",
        "href" => qr/(.*)/,
        sub
        {
            if ($_[0]->attr("href") =~ $item_link_pattern)
            {
                $item_name = $1;
                return 1;
            }
            elsif ($_[0]->attr("href") =~ $recipe_link_pattern)
            {
                $item_name = $2;
                return 1;
            }
            return 0;
        }
    );
    my $item_img_link = parse_img_link($_);

    unless(!$item_name)
    {
        $r{"name"} = $item_name;
    }
    unless(!$item_link_tag)
    {
        $item_link = $base_url . $item_link_tag->attr("href");
        $r{"link"} = $item_link;
    }
    unless(!$item_img_link)
    {
        $r{"img_link"} = $item_img_link;
    }
    
    return %r;
}

# ------------------------------------------------------------------------------
# MAIN - grab every item icon image from the Diablo III wiki on battle.net
# ------------------------------------------------------------------------------
my %items = ();
my $item_list_tree = HTML::TreeBuilder->new();

# fetch the item list page
my $item_list_content = get($item_list_url);

# parse the item list page
mkdir "images", 0755;
$item_list_tree->parse($item_list_content);
my @item_type_tags = $item_list_tree->look_down(
    "_tag" => "a",
    "href" => $item_link_pattern
);

# iterate through each item type and process all the items of that type
say "item type count: " . scalar(@item_type_tags);
foreach(@item_type_tags)
{
    #my $item_type_url = $base_url . $item_type_tags[0]->attr("href");
    my $item_type_url = $base_url . $_->attr('href');
    
    my $item_type = ();
    my $item_type_tree = HTML::TreeBuilder->new();

    # create an image dir for the item type
    if ($item_type_url =~ $item_link_pattern)
    {
        $item_type = $1;
        mkdir "images/" . $item_type, 0755;
    }

    # fetch and parse the item type page
    my $item_type_content = get($item_type_url);
    $item_type_tree->parse($item_type_content);

    # grab the total number of items of this type
    my $item_count = $item_type_tree->look_down("class" => "results-total");
    say $item_type . " [" . $item_count->as_trimmed_text() . " items found]";
    say $item_type_url;

    # grab the divs containing info about each item (in one of these classes):
    # "item-details-icon" - most armor and weapon types use this class
    # "data-cell" - smaller items use this class (potions, gems, etc)
    my @item_tags = $item_type_tree->look_down(
        "_tag" => "div",
        "class" => qr/(item-details-icon|data-cell)/
    );
    say "item tag count: " . scalar(@item_tags);
    
    # extract link and image info from each item tag, then follow the links
    my @img_links = ();
    foreach(@item_tags)
    {
        my $item_page_tree = HTML::TreeBuilder->new();
        
        # parse the item tag from the item type page and store the links
        my %item_info = parse_item($_);
        say "\t" . $item_info{"name"};
        say "\t\t" . $item_info{"link"};
        say "\t\t" . $item_info{"img_link"};
        push @img_links, $item_info{"img_link"};

        # fetch and parse the item page
        my $item_page_content = get($item_info{"link"});
        if (!$item_page_content)
        {
            say "error trying to fetch " . $item_info{"link"};
            next;
        }
        $item_page_tree->parse($item_page_content);
        
        # find any alternate images for the item (if they exist)
        my @alt_img_tags = $item_page_tree->look_down(
            "_tag" => "div",
            "class" => "icon-holder"
        );
        
        # add each alternate image to the list of image links
        foreach(@alt_img_tags)
        {
            my $alt_img_link = parse_img_link($_);
            say "\t\t" .  $alt_img_link;
            push @img_links, $alt_img_link;
        }
        
        # destroy the item page tree
        $item_page_tree = $item_page_tree->delete();
    }

    # add the unique image array for the item type to the item hash
    $items{$item_type} = [ unique(@img_links) ];

    # destroy the item type tree
    $item_type_tree = $item_type_tree->delete();
}

# destroy the item list tree
$item_list_tree = $item_list_tree->delete();

# iterate through the item hash and download images
foreach my $item_type_iter (keys %items)
{
    say "downloading type $item_type_iter:";
    foreach my $i ( 0 .. $#{ $items{$item_type_iter} } )
    {
        my $img_url = $items{$item_type_iter}[$i];
        if ($img_url =~ $img_filename_pattern)
        {
            my $filename = $2;
            print "  $i:\t$filename";
            my $code = getstore($img_url, "images/$item_type_iter/$filename");
            print "\t\t[$code]\n";
        }
    }
}

