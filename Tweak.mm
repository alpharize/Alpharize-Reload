#import <Foundation/Foundation.h>
#import "CPDistributedMessagingCenter.h"
#include <mach/mach.h>
#include <assert.h>
#include <stdio.h>
#include <unistd.h>
#include <dlfcn.h>

#import <mach/mach.h>
#import <mach/mach_traps.h>
#import <mach/vm_map.h>
#import <mach/vm_region.h>

#import <mach-o/arch.h>
#import <mach-o/dyld.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>

@interface ReloadObserver : NSObject
{
    CPDistributedMessagingCenter *center;
}
@end

struct dyld_image_info64 {
    uint64_t                   load_address_;  // struct mach_header_64*
    char                       *file_path_;
    uint64_t                   file_mod_date_;
};

struct dyld_all_image_infos64 {
    uint32_t                      version;  // == 1 in Mac OS X 10.4
    uint32_t                      infoArrayCount;
    const struct dyld_image_info64     *infoArray;
    uint64_t                      notification;
    bool                          processDetachedFromSharedRegion;
};

extern kern_return_t mach_vm_region
(
 vm_map_t target_task,
 mach_vm_address_t *address,
 mach_vm_size_t *size,
 vm_region_flavor_t flavor,
 vm_region_info_t info,
 mach_msg_type_number_t *infoCnt,
 mach_port_t *object_name
 );


extern kern_return_t mach_vm_read_overwrite
(
 vm_map_t target_task,
 mach_vm_address_t address,
 mach_vm_size_t size,
 mach_vm_address_t data,
 mach_vm_size_t *outsize
 );

extern kern_return_t mach_vm_protect
(
 vm_map_t target_task,
 mach_vm_address_t address,
 mach_vm_size_t size,
 boolean_t set_maximum,
 vm_prot_t new_protection
 );

extern kern_return_t mach_vm_write
(
 vm_map_t target_task,
 mach_vm_address_t address,
 vm_offset_t data,
 mach_msg_type_number_t dataCnt
 );


@implementation ReloadObserver

- (id)init
{
    if ((self = [super init]))
    {
        NSLog(@"Initializing server");
        center = [[%c(CPDistributedMessagingCenter) centerNamed:@"com.alpharize.proclivity"] retain];
        [center runServerOnCurrentThread];
        [center registerForMessageName:@"reload" target:self selector:@selector(reload:userInfo:)];
    }
    return self;
}

- (void)reload:(NSString *)name userInfo:(NSDictionary *)userInfo
{
    NSString* currentBundle = userInfo[@"bundle"];
    NSString* dylib = userInfo[@"dylib"];
    NSLog(@"Got reload for %@", currentBundle);
    CFBundleRef bundle(CFBundleGetMainBundle());
    CFStringRef _identifier(bundle == NULL ? NULL : CFBundleGetIdentifier(bundle));
    
    NSString* identifier = (__bridge NSString *)_identifier;
    NSLog(@"Current bundle: %@", identifier);
    if ([identifier isEqualToString:currentBundle]) {
        NSLog(@"Bundle matched!");
        task_dyld_info_data_t task_dyld_info;
        mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
        task_t self = mach_task_self();
        kern_return_t kr = task_info(self, TASK_DYLD_INFO ,(task_info_t)&task_dyld_info, &count);
        assert(kr == KERN_SUCCESS);
        mach_vm_address_t addr = task_dyld_info.all_image_info_addr;
        struct dyld_all_image_infos64 *info = (struct dyld_all_image_infos64*) addr;
        printf("%d\n", info->version);
        uint32_t ImageCount = info->infoArrayCount;
        NSLog(@"%d\n", ImageCount);
        
        for (int i = 0; i < ImageCount; ++i) {
            const struct dyld_image_info64 ImageInfo = info->infoArray[i];
            if ([[NSString stringWithUTF8String:ImageInfo.file_path_] isEqualToString:dylib]) {
                NSLog(@"dylib already loaded, bad idea, trying to dlclose (not reliable)");
                void* swag = (void*)ImageInfo.load_address_;
                dlclose(swag);
                return;
            }
            //NSLog(@"[dylib] %s %llx\n", ImageInfo.file_path_, ImageInfo.load_address_);
        }
        
        dlopen([dylib UTF8String], RTLD_LAZY | RTLD_GLOBAL);
        
    }
}

@end

__attribute__((constructor)) static void CmdAppLauncherTweak_Main()
{
    @autoreleasepool {
        NSLog(@"Proclivity-Reload loaded");
        [[ReloadObserver alloc] init];
    }
    
    
}
