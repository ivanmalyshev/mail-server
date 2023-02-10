#!/usr/bin/perl -w

# listPasswords.pl
#
# Please mail your comments and suggestions to <support@communigate.com>

####  YOU SHOLD REDEFINE THESE VARIABLES !!!

my $CGServerAddress='box.vrn.ru';  #IP or domain name;
my $Login='master';
my $Password='Utkb#C74Njg';

#### end of the customizeable variables list


use CLI;  #get one from www.stalker.com/CGPerl/
use strict;



my $cli = new CGP::CLI( { PeerAddr => $CGServerAddress,
                          PeerPort => 106,
                          login    => $Login,
	SecureLogin  => 0 ,
                          password => $Password } )
   || die "Can't login to CGPro: ".$CGP::ERR_STRING."\n";


#processAllDomains();
#processDomain('testbox.vrn.ru');
#exit ;
#processAccount ('mid@icmail.ru');
#processAccount ('molchanov@icmail.ru');
#processAccount ('filonovg@vmail.ru');
#processAccount ('bur@vmail.ru');
#processAccount ('vetrov@vmail.ru');
#processAccount ('sergk@vmail.ru');
#processAccount ('simson@vmail.ru');
#processAccount ('sherb@vmail.ru');
#processAccount ('bodral@icmail.ru');
#processAccount('sacha@testing.vrn.ru');
#processAccount ('chekmarev@icmail.ru');
#processAccount ('tvoyreklama@vmail.ru');
#processAccount ('test1@migrate.vrn.ru');
$cli->Logout();

exit;


sub processAllDomains {
  my $DomainList = $cli->ListDomains()
               || die "*** Can't get the domain list: ".$cli->getErrMessage.", quitting";
  foreach(@$DomainList) {
    processDomain($_);
  }
}         


sub processDomain {
  my $domain=$_[0];
#  print "Domain: $domain\n";

  my $cookie="";
  do {
    my $data=$cli->ListDomainObjects($domain,6032,undef,'ACCOUNTS',$cookie);
    unless($data) {
      print "*** Can't get accounts for $domain: ".$cli->getErrMessage."\n";
      return;
    }
    $cookie=$data->[4];
    foreach(keys %{$data->[1]} ) {
      processAccount("$_\@$domain"); 
    }
  }while($cookie ne '');
 
}



sub processAccount {
  my ($Account)=@_;
  my $accountPassword='???';
  if($cli->SendCommand("getaccountplainpassword $Account")) {
    if($cli->{errCode} eq 201) {
      $accountPassword=$cli->GetResponseData();
    }
  }
  print "$Account|$accountPassword|$Account|$accountPassword\n";
}


__END__

 
 
