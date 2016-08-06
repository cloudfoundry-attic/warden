How warden installation works
==============================

First, lets try to understand what the ```rake setup``` does, it creates 
a basic linux system under /tmp/warden directory using 2 basic tools:
debootstrap and chroot.  Deboostrap is a tool that setup a basic debian OS,
ubuntu is based on debian so that's the reason why we can use debootstrap to create
ubuntu systems too, basically you run: ```debootstrap [OPTION...]  SUITE TARGET [MIRROR [SCRIPT]]```
see (man deboostrap). After the installation you can use that system with chroot command
to run commands or interactive shell with a special root directory (see man chroot).


Try boostrap a Debian testing OS by hand running this command:

```
/usr/sbin/debootstrap --verbose --include openssh-server,rsync testing /tmp/my-debian-sandbox/rootfs http://ftp.de.debian.org/debian/

```

Now you can use this new system for testing purposes o for testing tasks that may
break the real system. To get "inside" into this new "cage":


```
chroot /tmp/my-debian-sandbox/rootfs
```

You are in. Every command you run will be running inside the new isolated system.


Coming back to our main goal, understanding warden setup, this new system will be used by warden
as a base root file system to run the containers, luckily you don't have to do all these steps by hand to have warden running
in your local debian system. I added a file in root/linux/rootfs/debian.sh in my warden's fork so you only
have to follow the instructions in the README file https://github.com/Altoros/warden/blob/master/warden/README.md . 


```
git clone git@github.com:Altoros/warden.git

cd warden/warden
sudo bundle
sudo bundle exec rake setup[config/linux.yml]
```

Playing with warden
====================

I'm stuck on the warden start rake task, I'm getting an error "mount: special device none does not exist":

https://gist.github.com/gramos/5981210

after a little of research on my system I figured out that cgroup support are not running, the 
debian package does not add any default config file and does not add any daemon, if you have some
ideas send me an email ramos.gaston at altoros dot com

Some data about my Debian OS:

```
uname -a
Linux noesmia 3.9-1-amd64 #1 SMP Debian 3.9.8-1 x86_64 GNU/Linux
```

```
dpkg -l | grep cgroup
ii  cgroup-bin                            0.38-1                             amd64        Tools to control and monitor control groups
ii  libcgroup1                            0.38-1                             amd64        Library to control and monitor control group

```

Update:
-------

I added some config files and now is working, I pushed the config files into a repo:

```
git clone git@github.com:gramos/cgroup-files.git

sudo cp -R cgroup-files/etc /etc
sudo /etc/init.d/cgrd start

```

Now you can run the setup again:

```
sudo bundle exec rake setup[config/linux.yml]
```

and then you can start the warden server:

```
sudo bundle exec rake warden:start[config/linux.yml]

```

and run the warden console client and create 2 new containers:


```
bundle exec bin/warden

warden> create
handle : 171hpgcl82u
warden> create
handle : 171hpgcl82v
warden> 

```

List the already created containers 

```
warden> list
handles[0] : 171hpgcl82u
handles[1] : 171hpgcl82v
warden>
```

You can see the directories of the containers:


```
ls -l /tmp/warden/containers/

drwxr-xr-x 9 root root 4096 Jul 15 13:55 171hpgcl82u
drwxr-xr-x 9 root root 4096 Jul 15 13:58 171hpgcl82v
drwxr-xr-x 2 root root 4096 Jul 15 12:18 tmp

```

If you take a look to the logs while you create a container, you can figure out that this is the flow more or less:


1. method: "set_deferred_success"
---------------------------------

  ```
  /home/gramos/src/altoros/warden/warden/lib/warden/container/spawn.rb
  ``` 

 
2. Create the container
-----------------------
   
   ```
   /home/gramos/src/altoros/warden/warden/root/linux/create.sh /tmp/warden/containers/171hpgcl831
   ```

3. method:"do_create"
---------------------
   
  ```
   /home/gramos/src/altoros/warden/warden/lib/warden/container/linux.rb 
   ```

4. Start the container
----------------------
  
  ```
  /tmp/warden/containers/171hpgcl831/start.sh
  ```

5. method: "write_snapshot"
--------------------------
  
  ```
  /home/gramos/src/altoros/warden/warden/lib/warden/container/base.rb  
  ``` 

6. method: "dispatch"
--------------------- 

  ```
  /home/gramos/src/altoros/warden/warden/lib/warden/container/base.rb 
  ```


Delete a container:

```
warden> destroy --handle 171hpgcl82u
```

For some reason that I don't know yet, the destroy commands hangs and it never returns the warden prompt

