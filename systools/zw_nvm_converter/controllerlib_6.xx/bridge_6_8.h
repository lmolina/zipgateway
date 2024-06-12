/* © 2019 Silicon Laboratories Inc. */
#include"nvm_desc.h"
#define bridge_6_8_app_version 0x0606
#define bridge_6_8_zw_version 0x0606
const nvm_desc_t bridge_6_8[] = {
{ "nvmTotalEnd","WORD", 0x0000, 1 },
{ "nvmZWlibrarySize","WORD", 0x0002, 1 },
{ "NVM_INTERNAL_RESERVED_1_far","BYTE", 0x0004, 4 },
{ "EX_NVM_HOME_ID_far","BYTE", 0x0008, HOMEID_LENGTH },
{ "NVM_INTERNAL_RESERVED_2_far","BYTE", 0x000c, 4 },
{ "NVM_HOMEID_far","BYTE", 0x0010, HOMEID_LENGTH },
{ "NVM_NODEID_far","BYTE", 0x0014, 1 },
{ "NVM_CONFIGURATION_VALID_far","BYTE", 0x0015, 1 },
{ "NVM_CONFIGURATION_REALLYVALID_far","BYTE", 0x0016, 1 },
{ "NVM_INTERNAL_RESERVED_3_far","BYTE", 0x0017, 1 },
{ "NVM_PREFERRED_REPEATERS_far","BYTE", 0x0018, MAX_NODEMASK_LENGTH + 3 },
{ "NVM_PENDING_DISCOVERY_far","BYTE", 0x0038, MAX_NODEMASK_LENGTH + 3 },
{ "NVM_RTC_TIMERS_far","BYTE", 0x0058, TOTAL_RTC_TIMER_MAX * RTC_TIMER_SIZE },
{ "EX_NVM_NODE_TABLE_START_far","EX_NVM_NODEINFO", 0x00f8, ZW_MAX_NODES },
{ "EX_NVM_ROUTING_TABLE_START_far","NODE_MASK_TYPE", 0x0580, ZW_MAX_NODES },
{ "EX_NVM_LAST_USED_NODE_ID_START_far","BYTE", 0x1fc8, 1 },
{ "EX_NVM_STATIC_CONTROLLER_NODE_ID_START_far","BYTE", 0x1fc9, 1 },
{ "EX_NVM_PENDING_UPDATE_far","NODE_MASK_TYPE", 0x1fca, 1 },
{ "EX_NVM_SUC_ACTIVE_START_far","BYTE", 0x1fe7, 1 },
{ "EX_NVM_SUC_NODE_LIST_START_far","SUC_UPDATE_ENTRY_STRUCT", 0x1fe8, SUC_MAX_UPDATES },
{ "EX_NVM_SUC_CONTROLLER_LIST_START_far","BYTE", 0x2568, SUC_CONTROLLER_LIST_SIZE },
{ "EX_NVM_SUC_LAST_INDEX_START_far","BYTE", 0x2650, 1 },
{ "EX_NVM_SUC_ROUTING_SLAVE_LIST_START_far","NODE_MASK_TYPE", 0x2651, 1 },
{ "EX_NVM_ZENSOR_TABLE_START_far","NODE_MASK_TYPE", 0x266e, 1 },
{ "EX_NVM_BRIDGE_NODEPOOL_START_far","NODE_MASK_TYPE", 0x268b, 1 },
{ "EX_NVM_CONTROLLER_CONFIGURATION_far","BYTE", 0x26a8, 1 },
{ "EX_NVM_MAX_NODE_ID_far","BYTE", 0x26a9, 1 },
{ "EX_NVM_RESERVED_ID_far","BYTE", 0x26aa, 1 },
{ "EX_NVM_ROUTECACHE_START_far","ROUTECACHE_LINE", 0x26ab, ZW_MAX_NODES },
{ "EX_NVM_ROUTECACHE_NLWR_SR_START_far","ROUTECACHE_LINE", 0x2b33, ZW_MAX_NODES },
{ "EX_NVM_ROUTECACHE_MAGIC_far","BYTE", 0x2fbb, 1 },
{ "EX_NVM_ROUTECACHE_APP_LOCK_far","BYTE", 0x2fbc, MAX_NODEMASK_LENGTH },
{ "NVM_SECURITY0_KEY_far","BYTE", 0x2fd9, 16 },
{ "NVM_SYSTEM_STATE","BYTE", 0x2fe9, 1 },
{ "nvmZWlibraryDescriptor","t_nvmModuleDescriptor", 0x2fea, 1 },
{ "nvmApplicationSize","WORD", 0x2fef, 1 },
{ "EEOFFSET_MAGIC_far","BYTE", 0x2ff1, 1 },
{ "EEOFFSET_CMDCLASS_LEN_far","BYTE", 0x2ff2, 1 },
{ "EEOFFSET_CMDCLASS_far","BYTE", 0x2ff3, APPL_NODEPARM_MAX },
{ "EEOFFSET_WATCHDOG_STARTED_far","BYTE", 0x3016, 1 },
{ "EEOFFSET_POWERLEVEL_NORMAL_far","BYTE", 0x3017, POWERLEVEL_CHANNELS },
{ "EEOFFSET_POWERLEVEL_LOW_far","BYTE", 0x301a, POWERLEVEL_CHANNELS },
{ "EEOFFSET_MODULE_POWER_MODE_EXTINT_ENABLE_far","BYTE", 0x301d, 1 },
{ "EEOFFSET_MODULE_POWER_MODE_far","BYTE", 0x301e, 1 },
{ "EEOFFSET_MODULE_POWER_MODE_WUT_TIMEOUT_far","BYTE", 0x301f, sizeof(DWORD) },
{ "nvmApplicationDescriptor","t_nvmModuleDescriptor", 0x3023, 1 },
{ "nvmHostApplicationSize","WORD", 0x3028, 1 },
{ "EEOFFSET_HOST_OFFSET_START_far","BYTE", 0x302a, NVM_SERIALAPI_HOST_SIZE },
{ "nvmHostApplicationDescriptor","t_nvmModuleDescriptor", 0x382a, 1 },
{ "nvmDescriptorSize","WORD", 0x382f, 1 },
{ "nvmDescriptor","t_NvmModuleSize", 0x3831, 1 },
{ "nvmDescriptorDescriptor","t_nvmModuleDescriptor", 0x383d, 1 },
{ "nvmModuleSizeEndMarker","WORD", 0x3842, 1 },
};
