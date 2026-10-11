#include <libproc.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
int main(int argc,char **argv){
 if(argc!=3)return 2;int pid=atoi(argv[1]),count=atoi(argv[2]);if(count<1||count>301)return 2;
 printf("time,user_ns,system_ns,footprint,resident,disk_read,disk_write,fd_count\n");
 for(int i=0;i<count;i++){
  struct rusage_info_v4 r={0};if(proc_pid_rusage(pid,RUSAGE_INFO_V4,(rusage_info_t*)&r)!=0)return 3;
  int capacity=proc_pidinfo(pid,PROC_PIDLISTFDS,0,NULL,0);
  if(capacity<=0)return 4;
  struct proc_fdinfo *fds=malloc((size_t)capacity);
  if(!fds)return 5;
  int bytes=proc_pidinfo(pid,PROC_PIDLISTFDS,0,fds,capacity);
  free(fds);
  if(bytes<0)return 4;
  printf("%ld,%llu,%llu,%llu,%llu,%llu,%llu,%lu\n",time(NULL),r.ri_user_time,r.ri_system_time,r.ri_phys_footprint,r.ri_resident_size,r.ri_diskio_bytesread,r.ri_diskio_byteswritten,bytes/sizeof(struct proc_fdinfo));fflush(stdout);
  if(i+1<count)sleep(5);
 }return 0;
}
