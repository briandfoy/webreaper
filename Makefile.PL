# $Id$
use ExtUtils::MakeMaker;

sub ExtUtils::MM_Any::test_via_harness
	{
    my($self, $perl, $tests) = @_;

    return qq|\t$perl "-MTest::Manifest" | .
           qq|"-e" "run_t_manifest(\$(TEST_VERBOSE), '\$(INST_LIB)', | .
           qq|'\$(INST_ARCHLIB)')"\n|;
	}

WriteMakefile(
    'NAME'		    => 'webreaper',
	'VERSION'       => '0.11',
	
	'EXE_FILES' =>  [ 'webreaper' ],
	    	
	'PREREQ_PM' => {
		'File::Find::Rule'  => '0',
		'Test::File'        => '0',
		'Test::Manifest'    => '0.91',
		'Test::More'        => '0',
		'Test::Pod'         => '0.90',
		},

	'MAN1PODS' => {
		'webreaper' => '$(INST_MAN1DIR)/webreaper.1',
		},
		
	clean => { FILES => '*.bak webreaper-*' },
	);
