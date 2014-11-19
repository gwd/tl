#!/usr/bin/perl
$bridge="xenbr0";

#print "Looking for ip associated with mac $mac\n";
sub ip2n
{
    my $a;

    if($_[0]=~/([0-9]*)\.([0-9]*)\.([0-9]*)\.([0-9]*)/)
    {
	$a=((($1*256+$2)*256+$3)*256+$4)
    }
    return $a;
}




sub foundip
{
    my $tmac, $tip, $tipnet_n;

    ($tmac,$tip)=@_;

    # Only log 
    $tipnet_n = ip2n($tip) & $hostmask_n;

    #printf "%x %x %x %x\n",$hostmask_n,$hostip_n,ip2n($tip),$tipnet_n;

    if ( $tipnet_n != $hostnet_n )
    {
	return;
    }
    
    # if($tip eq "0.0.0.0"
    #    || $tip=~/^192.168/)
    # {
    # 	return;
    # }

    if(!defined $hash{$tmac}
       || $hash{$tmac} ne $tip)
    {
	$hash{$tmac}=$tip;
	print ARPLOG "$tmac $tip\n";
    }
}

sub hostnet
{
    $_=`ip addr show dev $bridge`;
    /inet ([0-9.]+)\/([0-9]+) / || die "Cannot find $bridge addr/shift: $output";
    $hostip=$1;
    $hostmask_prefix=$2;
    print STDERR "Host ip: $hostip prefix: $hostmask_prefix\n";
    
    # Convert to numbers so that we can easily do bitwise operations on them
    $hostip_n=ip2n($hostip);
    $hostmask_n = (((1<<32)-1) << (32-$hostmask_prefix)) & ((1<<32)-1);
    $hostnet_n = $hostip_n & $hostmask_n;
    printf STDERR "Hostmask: 0x%x\n", $hostmask_n;

    # Sanity check comparing to old way
    if(0) {
	$_=`ifconfig $bridge`;
	# /inet addr:([0-9.]+)/ || die "Cannot find $bridge addr: $output";
	/Mask:([0-9.]+)/ || die "Cannot find netmask: $output";
	$t_hostmask=$1;
	print STDERR "Test host mask: $t_hostmask\n";
	$t_hostmask_n=ip2n($t_hostmask);
	printf STDERR "Test hostmask: 0x%x\n", $t_hostmask_n;
	if ($t_hostmask_n != $hostmask_n) {
	    die;
	}
    }
}

open ARPLOG, ">", "/var/local/arp.log";
select ARPLOG; $|=1;
open ARPDEBUG, ">", "/var/local/arpdebug.log";
select ARPDEBUG; $|=1;

hostnet;

open TCPDUMP, "tcpdump -lne -i $bridge arp or udp port bootps |"
    or die "tcpdump failed";

while(<TCPDUMP>) {
    #print ARPDEBUG;

    if(/> ([0-9a-f:]+).*> ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).bootpc: BOOTP\/DHCP, Reply/) {
	foundip $1,$2;
    }

    # 11:27:24.414321 00:21:1b:f3:63:45 > 00:16:3e:0c:01:01, ethertype IPv4 (0x0800), length 342: 10.80.224.1.67 > 10.80.237.129.68: BOOTP/DHCP, Reply, length 300
    if(/> ([0-9a-f:]+).*> ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+): BOOTP\/DHCP, Reply/) {
	foundip $1,$2;
    }
    if(/> ([0-9a-f:]+).*> ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).68: BOOTP\/DHCP, Reply/) {
	foundip $1,$2;
    }

    if(/\s+([0-9a-f:]+)\s+>\s+Broadcast.*ARP.*tell\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/) {
	foundip $1,$2;
    }

    # 11:27:37.738599 00:16:3e:0c:01:01 > ff:ff:ff:ff:ff:ff, ethertype ARP (0x0806), length 42: Request who-has 10.80.224.1 tell 10.80.237.129, length 28
    if(/\s+([0-9a-f:]+)\s+>\s+ff:ff:ff:ff:ff:ff.*ARP.*tell\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/) {
	foundip $1,$2;
    }

    if(/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) is-at ([0-9a-f:]+)/) {
# NB that the order is ip,mac, unlike the other two.
	foundip $2,$1;
    }
    #11:27:37.739272 00:21:1b:f3:63:45 > 00:16:3e:0c:01:01, ethertype ARP (0x0806), length 60: Reply 10.80.224.1 is-at 00:21:1b:f3:63:45, length 46
    if(/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) is-at ([0-9a-f:]+)/) {
	foundip $2,$1;
    }
    
}

close TCPDUMP
