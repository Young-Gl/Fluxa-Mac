/* Fluxa local-device reader. Independent implementation using libimobiledevice's C API.
 * Queries only an existing trust relationship; never creates one or changes Wi-Fi settings.
 */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include <unistd.h>
typedef void *node;
static node (*new_array)(void), (*new_dict)(void), (*new_string)(const char*), (*copy_node)(node), (*dict_get)(node,const char*), (*array_get)(node,uint32_t);
static void (*dict_set)(node,const char*,node), (*array_append)(node,node), (*free_node)(node), (*get_string)(node,char**);
static uint32_t (*array_size)(node);
static int (*to_xml)(node,char**,uint32_t*), (*get_type)(node);
static int (*cpx_get)(void*,const char*,const char*,node*);
static int (*cpx_new)(void*,void**,const char*), (*cpx_free)(void*);
static void field(node output, const char *key, node value) { if(value) dict_set(output,key,copy_node(value)); }
static void watch_field(void *device, const char *id, const char *key, node output, const char *outkey) {
 void *cpx=NULL;
 if(cpx_new(device,&cpx,"Fluxa")!=0 || !cpx)return;
 node reply=NULL;
 if(cpx_get(cpx,id,key,&reply)==0 && reply) {
  node value=dict_get(reply,key);
  if(value) field(output,outkey,value);
 }
 if(reply) free_node(reply);cpx_free(cpx);
}
#define LOAD(handle,var,symbol) do { *(void **)(&(var))=dlsym(handle,symbol); if(!(var)) return 3; } while(0)
int main(int argc,char **argv) {
 if((argc!=3 && argc!=4) || strlen(argv[1])>64) return 2;
 int read_phone=(argc==3 || strcmp(argv[3],"watch"));
 int read_watch=(argc==3 || !strcmp(argv[3],"watch"));
 char executable[PATH_MAX],base[PATH_MAX],path[PATH_MAX]; uint32_t length=sizeof(executable);
 if(_NSGetExecutablePath(executable,&length)!=0 || !realpath(executable,base)) return 3;
 char *slash=strrchr(base,'/'); if(!slash) return 3; *slash=0;
 snprintf(path,sizeof(path),"%s/../lib/libusbmuxd.dylib",base);
 void *mux=dlopen(path,RTLD_NOW|RTLD_LOCAL); if(!mux) return 3;
 int (*pair_record)(const char*,char**,uint32_t*); LOAD(mux,pair_record,"usbmuxd_read_pair_record");
 char *record=NULL; uint32_t size=0; int pair=pair_record(argv[1],&record,&size); free(record);
 if(pair!=0 || !size) {dlclose(mux);return 4;}
 snprintf(path,sizeof(path),"%s/../lib/libimobiledevice.dylib",base);
 void *lib=dlopen(path,RTLD_NOW|RTLD_LOCAL); if(!lib) {dlclose(mux);return 3;}
 LOAD(lib,new_array,"plist_new_array"); LOAD(lib,new_dict,"plist_new_dict"); LOAD(lib,new_string,"plist_new_string");
 LOAD(lib,copy_node,"plist_copy"); LOAD(lib,dict_get,"plist_dict_get_item"); LOAD(lib,dict_set,"plist_dict_set_item");
 LOAD(lib,array_get,"plist_array_get_item"); LOAD(lib,array_size,"plist_array_get_size"); LOAD(lib,array_append,"plist_array_append_item");
 LOAD(lib,free_node,"plist_free"); LOAD(lib,to_xml,"plist_to_xml"); LOAD(lib,get_string,"plist_get_string_val"); LOAD(lib,get_type,"plist_get_node_type");
 int (*device_new)(void**,const char*,int), (*device_free)(void*), (*lock_new)(void*,void**,const char*), (*lock_free)(void*), (*lock_get)(void*,const char*,const char*,node*);
 int (*cpx_registry)(void*,node*);
 LOAD(lib,device_new,"idevice_new_with_options"); LOAD(lib,device_free,"idevice_free");
 LOAD(lib,lock_new,"lockdownd_client_new_with_handshake"); LOAD(lib,lock_free,"lockdownd_client_free"); LOAD(lib,lock_get,"lockdownd_get_value");
 LOAD(lib,cpx_new,"companion_proxy_client_start_service"); LOAD(lib,cpx_free,"companion_proxy_client_free");
 LOAD(lib,cpx_registry,"companion_proxy_get_device_registry"); LOAD(lib,cpx_get,"companion_proxy_get_value_from_registry");
 int network=!strcmp(argv[2],"network"); void *device=NULL,*lock=NULL;
 if(device_new(&device,argv[1],network?4:2)!=0 || !device) {dlclose(lib);dlclose(mux);return 5;}
 if(lock_new(device,&lock,"Fluxa")!=0 || !lock) {device_free(device);dlclose(lib);dlclose(mux);return 6;}
 node result=new_array(),phone=new_dict(),value=NULL;
 if(read_phone) {
 dict_set(phone,"ID",new_string(argv[1])); dict_set(phone,"Source",new_string(network?"Wi-Fi":"USB"));
 if(lock_get(lock,NULL,"DeviceName",&value)==0 && value) field(phone,"Name",value); if(value)free_node(value);value=NULL;
 if(lock_get(lock,NULL,"DeviceClass",&value)==0 && value) field(phone,"Kind",value); if(value)free_node(value);value=NULL;
 if(lock_get(lock,"com.apple.mobile.battery",NULL,&value)==0 && value) {
  field(phone,"BatteryCurrentCapacity",dict_get(value,"BatteryCurrentCapacity")); field(phone,"BatteryIsCharging",dict_get(value,"BatteryIsCharging"));
 }
 if(value)free_node(value); array_append(result,phone);
 } else {free_node(phone);}
 lock_free(lock);
 void *cpx=NULL; node registry=NULL;
 if(read_watch && cpx_new(device,&cpx,"Fluxa")==0 && cpx) {
  if(cpx_registry(cpx,&registry)==0 && registry) {
   uint32_t n=array_size(registry); if(n>8)n=8;
   for(uint32_t i=0;i<n;i++) {
    char *id=NULL; get_string(array_get(registry,i),&id); if(!id)continue;
    node watch=new_dict(); dict_set(watch,"ID",new_string(id)); dict_set(watch,"Kind",new_string("Watch"));
    dict_set(watch,"Source",new_string(network?"iPhone · Wi-Fi":"iPhone · USB"));
    watch_field(device,id,"BatteryCurrentCapacity",watch,"BatteryCurrentCapacity");
    watch_field(device,id,"BatteryIsCharging",watch,"BatteryIsCharging");
    watch_field(device,id,"DeviceName",watch,"Name");
    array_append(result,watch);free(id);
   }
  }
  if(registry)free_node(registry);cpx_free(cpx);
 }
 device_free(device);
 char *xml=NULL; uint32_t xml_size=0; int status=to_xml(result,&xml,&xml_size);
 if(!status && xml && xml_size<262144) fwrite(xml,1,xml_size,stdout);
 free(xml);free_node(result);dlclose(lib);dlclose(mux);return status?7:0;
}
