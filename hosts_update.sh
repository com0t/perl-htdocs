hn=`hostname`
if ! grep -q $hn /etc/hosts
then
        echo "127.0.0.1 $hn" >> /etc/hosts
fi
