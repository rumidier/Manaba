package Manaba;
use Dancer ':syntax';

our $VERSION = '0.1';

use 5.010;
use File::Path qw( make_path );
use File::Slurp;
use LWP::UserAgent;
use URI;
use Web::Scraper;
use YAML::Tiny;

my $ua = Web::Scraper::user_agent;
$ua->agent(
    'Mozilla/5.0'
    . ' (Windows; U; Windows NT 6.1; en-US; rv:1.9.2b1)'
    . ' Gecko/20091014 Firefox/3.6b1 GTB5'
);

my $CONFIG;
my $SCRAPERS = {
    daum => scraper {
        process(
            'div.episode_list > div.inner_wrap > div.scroll_wrap > ul > li',
            'items[]',
            scraper {
                process 'a.img', link  => '@href';
                process 'a.img', title => '@title';
            }
        );
    },
    naver => scraper {
        process(
            'table.viewList tr td.title',
            'items[]',
            scraper {
                process 'a', link => '@href';
            }
        );
    },
    nate => scraper {
        process(
            'div.wrap_carousel div.thumbPage div.thumbSet dd',
            'items[]',
            scraper {
                process 'a',   link  => '@href';
                process 'img', title => '@alt';
            }
        );
    },
};

get '/' => sub {
    my $webtoon = $CONFIG->{webtoon};

    my @items = map {
        my $item = $webtoon->{$_};

        $item->{id}    = $_;
        $item->{first} = q{} unless $item->{first};
        $item->{last}  = q{} unless $item->{last};

        $item;
    } sort keys %$webtoon;

    template 'index' => {
        items => [
            @items,
        ],
    };
};

get '/update/:id?' => sub {
    my $id = param('id');

    if ($id) {
        update($id);
    }
    else {
        update_all();
    }

    redirect '/';
};

sub update {
    my $id = shift;

    return unless $id;

    my $webtoon = $CONFIG->{webtoon};
    return unless $webtoon;

    my $site_name = $webtoon->{$id}{site};
    return unless $site_name;

    my $scraper = $SCRAPERS->{ $site_name };
    return unless $scraper;

    my $site = $CONFIG->{site};
    return unless $site;

    my $start_url = sprintf(
        $site->{ $site_name }{ 'start_url' },
        $webtoon->{$id}{ 'code' },
    );

    my $items = $scraper->scrape( URI->new( $start_url ) )->{items};
    my @links = map { $_->{link} } @$items;

    given ( $site_name ) {
        update_daum_link($id, @links)  when 'daum';
        update_naver_link($id, @links) when 'naver';
        update_nate_link($id, @links)  when 'nate';
    }
}

sub update_all {
    my $webtoons = $CONFIG->{webtoon};

    for my $id ( keys %$webtoons ) {
        update($id);
    }
}

sub update_daum_link {
    my ( $id, @links ) = @_;

    my $webtoon = $CONFIG->{webtoon};
    return unless $webtoon;

    my $site = $CONFIG->{site};
    return unless $site;

    my $webtoon_url = $site->{ $webtoon->{$id}{site} }{webtoon_url};
    return unless $webtoon_url;

    my @chapters = sort {
        my $page_no_a = 0;
        my $page_no_b = 0;

        $page_no_a = $1 if $a =~ m/^(\d+)$/;
        $page_no_b = $1 if $b =~ m/^(\d+)$/;

        $page_no_a <=> $page_no_b;
    } map {
        m{viewer/(\d+)$};
    } @links;

    $webtoon->{$id}{first} = sprintf( $webtoon_url, $chapters[0] );
    $webtoon->{$id}{last}  = sprintf( $webtoon_url, $chapters[-1] );
}

sub update_naver_link {
    my ( $id, @links ) = @_;

    my $webtoon = $CONFIG->{webtoon};
    return unless $webtoon;

    my $site = $CONFIG->{site};
    return unless $site;

    my $webtoon_url = $site->{ $webtoon->{$id}{site} }{webtoon_url};
    return unless $webtoon_url;

    my @chapters = sort {
        my $page_no_a = 0;
        my $page_no_b = 0;

        $page_no_a = $1 if $a =~ m/^(\d+)$/;
        $page_no_b = $1 if $b =~ m/^(\d+)$/;

        $page_no_a <=> $page_no_b;
    } map {
        m{no=(\d+)};
    } @links;

    $webtoon->{$id}{first} = sprintf( $webtoon_url, $webtoon->{$id}{code}, 1 );
    $webtoon->{$id}{last}  = sprintf( $webtoon_url, $webtoon->{$id}{code}, $chapters[-1] );
}

sub update_nate_link {
    my ( $id, @links ) = @_;

    my $webtoon = $CONFIG->{webtoon};
    return unless $webtoon;

    my $site = $CONFIG->{site};
    return unless $site;

    my $webtoon_url = $site->{ $webtoon->{$id}{site} }{webtoon_url};
    return unless $webtoon_url;

    my @chapters = sort {
        my $page_no_a = 0;
        my $page_no_b = 0;

        $page_no_a = $1 if $a =~ m/^(\d+)$/;
        $page_no_b = $1 if $b =~ m/^(\d+)$/;

        $page_no_a <=> $page_no_b;
    } map {
        m{bsno=(\d+)$};
    } @links;

    $webtoon->{$id}{first} = sprintf( $webtoon_url, $webtoon->{$id}{code}, $chapters[0] );
    $webtoon->{$id}{last}  = sprintf( $webtoon_url, $webtoon->{$id}{code}, $chapters[-1] );
}

sub load_manaba {
    my $yaml = YAML::Tiny->read( config->{manaba} );
    $CONFIG = $yaml->[0];
}

sub fetch_webtoon_image {
    my $ua = Web::Scraper::user_agent;
    return unless $ua;

    return unless $CONFIG;

    my $webtoons = $CONFIG->{webtoon};
    return unless $webtoons;

    make_path('public/images/webtoon');
    for my $id ( keys %$webtoons ) {
        my $file = "public/images/webtoon/$id";
        next if -f $file;

        my $response = $ua->get( $webtoons->{$id}{image} );
        if ($response->is_success) {
            write_file( $file, $response->content );
        }
    }
}

load_manaba();
fetch_webtoon_image();
update_all();

true;
