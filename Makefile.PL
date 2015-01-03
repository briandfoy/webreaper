use ExtUtils::MakeMaker 6.48;

require 5.014;

eval "use Test::Manifest 0.21";

WriteMakefile(
    'NAME'		    => 'webreaper',
	'ABSTRACT'      => 'Scrape entire websites',
	'VERSION'       => '1.01',
	'LICENSE'		=> 'perl',
	'AUTHOR'		=> 'brian d foy <bdfoy@cpan.org>',
	
	'EXE_FILES' =>  [ 'webreaper' ],
	    	
	'PREREQ_PM' => {
		'HTML::SimpleLinkExtor'  => '0',
		'Mojolicious::UserAgent' => '0',
		},

	'MAN1PODS' => {
		'webreaper' => '$(INST_MAN1DIR)/webreaper.1',
		},
		
	clean => { FILES => '*.bak webreaper-*' },
	);
