#!/usr/bin/perl
use strict;
use warnings;
use JSON;

# =============================================================================
# check_nvme_smart_all.pl
#
# Purpose:
#   Monitor all NVMe devices on the system using nvme-cli.
#   Collect SMART data and report to Nagios/Icinga via NRPE.
#
# Requirements:
#   - Perl with JSON module
#   - nvme-cli installed (usually /usr/sbin/nvme)
#   - NRPE installed and running
#   - nagios user must have sudo access for nvme commands (see below)
#
# NRPE / sudo setup example:
#   1. Install NRPE:
#        apt install nagios-nrpe-server nagios-plugins
#   2. Create sudoers file:
#        sudo visudo -f /etc/sudoers.d/nvme-nagios
#        Add line:
#           nagios ALL=(root) NOPASSWD: /usr/sbin/nvme smart-log *, /usr/sbin/nvme list -o json
#        chmod 440 /etc/sudoers.d/nvme-nagios
#   3. Test as nagios user:
#        sudo -u nagios sudo nvme list -o json
#        sudo -u nagios sudo nvme smart-log /dev/nvme0n1 -o json
#   4. Modify this script to call 'sudo nvme ...'
#
# Variables / thresholds:
#   TEMP_WARN / TEMP_CRIT       - Temperature Celsius
#   SPARE_WARN / SPARE_CRIT     - Available spare %
#   MEDIA_CRIT                  - Media errors threshold
#   UNSAFE_CRIT                 - Unsafe shutdowns threshold (100)
# =============================================================================


# Thresholds
# -----------------------------
my $TEMP_WARN    = 70;   # Celsius
my $TEMP_CRIT    = 80;
my $SPARE_WARN   = 20;   # percent
my $SPARE_CRIT   = 10;
my $MEDIA_CRIT   = 1;
my $UNSAFE_CRIT  = 100;  # unsafe shutdowns


# Helper functions
# -----------------------------
sub data_units_to_mb { 
    my ($val) = @_; 
    return 0 unless defined $val; 
    return int($val * 512 / 1024);  # 1 unit = 512 bytes → MB
}

sub kelvin_to_c { return int($_[0]-273.15+0.5); }
sub safe_value { return $_[0] // 0; }


# Get NVMe devices
# -----------------------------
my $nvme_list_json = `sudo nvme list -o json 2>/dev/null`;
if ($? != 0 || !$nvme_list_json) { print "UNKNOWN - Failed to run 'nvme list'\n"; exit 3; }

my $nvme_data = eval { decode_json($nvme_list_json) };
if ($@) { print "UNKNOWN - Failed to parse JSON: $@\n"; exit 3; }

my @devices;
if (exists $nvme_data->{Devices} && ref($nvme_data->{Devices}) eq 'ARRAY') {
    @devices = @{$nvme_data->{Devices}};
} else {
    print "UNKNOWN - No NVMe devices found\n"; exit 3;
}


# Overall tracking
# -----------------------------
my $overall_status = 0;  # 0=OK,1=WARN,2=CRIT,3=UNKNOWN
my $overall_text = '';
my $perfdata = '';


# Process each device
# -----------------------------
foreach my $dev (@devices) {
    my $node = $dev->{DevicePath};
    next unless $node;
    my $name_short = $node; $name_short =~ s{^/dev/}{};

    # Compute usage in GB
    my $used_gb = sprintf("%.1f", safe_value($dev->{UsedBytes}) / 1024 / 1024 / 1024);
    my $max_gb  = sprintf("%.1f", safe_value($dev->{PhysicalSize}) / 1024 / 1024 / 1024);

    # SMART log JSON
    my $smart_json = `sudo nvme smart-log $node -o json 2>/dev/null`;
    if ($? != 0 || !$smart_json) {
        $overall_text .= "CRITICAL - $node: failed SMART; \n";
        $overall_status = 2 if $overall_status < 2;
        next;
    }

    my $smart = eval { decode_json($smart_json) };
    if ($@) {
        $overall_text .= "UNKNOWN - $node: failed parse SMART; \n";
        $overall_status = 3 if $overall_status < 3;
        next;
    }

    # Extract SMART values
    my $temp_c   = kelvin_to_c(safe_value($smart->{temperature}));
    my $spare    = safe_value($smart->{avail_spare});
    my $spare_thr= safe_value($smart->{spare_thresh});
    my $percent_wear = safe_value($smart->{percent_used});
    my $endurance_warn = safe_value($smart->{endurance_grp_critical_warning_summary});
    my $data_read_mb  = data_units_to_mb($smart->{data_units_read});
    my $data_written_mb = data_units_to_mb($smart->{data_units_written});
    my $media_errors = safe_value($smart->{media_errors});
    my $unsafe_shutdowns = safe_value($smart->{unsafe_shutdowns});
    my $critical_warn = safe_value($smart->{critical_warning});
    my $power_cycles = safe_value($smart->{power_cycles});

    # Determine device status
    my ($dev_status, $emoji, $exit_code) = ("OK","✅",0);
    if ($temp_c >= $TEMP_CRIT ||
        $spare < $SPARE_CRIT ||
        $media_errors >= $MEDIA_CRIT ||
        $unsafe_shutdowns >= $UNSAFE_CRIT ||
        $critical_warn != 0 ||
        $endurance_warn != 0) {
        ($dev_status, $emoji, $exit_code) = ("CRITICAL","🔥",2);
    } elsif ($temp_c >= $TEMP_WARN || $spare < $SPARE_WARN) {
        ($dev_status, $emoji, $exit_code) = ("WARNING","⚠️",1);
    }
    $overall_status = $exit_code if $exit_code > $overall_status;

    # Text summary with emoji and line break
    $overall_text .= sprintf(
        "%s %s - %s [%s, %s, FW %s, Written %s GB, Wear %s%%]: Temp %dC, Spare %s%%, MediaErr %d;\n",
        $emoji, $dev_status, $node, $dev->{SerialNumber}//'unknown', $dev->{ModelNumber}//'unknown',
        $dev->{Firmware}//'unknown', $used_gb, $percent_wear, $temp_c, $spare, $media_errors
    );

    # Perfdata (temperature first)
    $perfdata .= sprintf(
        "'%s_temperature'=%dC;%d;%d '%s_available_spare'=%s;%d;%d '%s_percent_wear'=%s '%s_used_gb'=%s '%s_data_read'=%dMB '%s_data_written'=%dMB '%s_power_cycles'=%d '%s_unsafe_shutdowns'=%d '%s_media_errors'=%d ",
        $name_short,$temp_c,$TEMP_WARN,$TEMP_CRIT,
        $name_short,$spare,$SPARE_WARN,$SPARE_CRIT,
        $name_short,$percent_wear,
        $name_short,$used_gb,
        $name_short,$data_read_mb,
        $name_short,$data_written_mb,
        $name_short,$power_cycles,
        $name_short,$unsafe_shutdowns,
        $name_short,$media_errors
    );
}


# Output result
# -----------------------------
if (!$overall_text) {
    print "UNKNOWN - No NVMe devices or SMART info available\n";
    exit 3;
}

print "$overall_text|$perfdata\n";
exit $overall_status;

