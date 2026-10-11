"""Generate Fluxa's macOS Widget Extension target (no package-manager dependency)."""
from pathlib import Path
import hashlib
import plistlib

objects = {}


def obj(key, isa, **args):
    identity = hashlib.sha256(('Fluxa:' + key).encode()).hexdigest()[:24].upper()
    objects[identity] = {'isa': isa, **args}
    return identity


refs, files = [], []
for path in ['Shared/DeviceBattery.swift', 'Shared/BatteryRings.swift', 'Widget/FluxaWidget.swift']:
    ref = obj(path, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=path, sourceTree='SOURCE_ROOT')
    refs.append(ref)
    files.append(obj(path + 'build', 'PBXBuildFile', fileRef=ref))
product = obj('product', 'PBXFileReference', explicitFileType='wrapper.app-extension', path='FluxaWidget.appex', sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products', 'PBXGroup', children=[product], name='Products', sourceTree='<group>')
main = obj('group', 'PBXGroup', children=refs + [products], sourceTree='<group>')
sources = obj('sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)
frameworks = obj('frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
settings = {
    'PRODUCT_BUNDLE_IDENTIFIER': 'local.hanchao.Watts.Widget', 'PRODUCT_NAME': 'FluxaWidget',
    'SWIFT_VERSION': '5.0', 'SDKROOT': 'macosx', 'MACOSX_DEPLOYMENT_TARGET': '14.0',
    'INFOPLIST_FILE': 'Widget/Info.plist', 'CODE_SIGN_ENTITLEMENTS': 'Widget/Widget.entitlements',
    'CODE_SIGNING_ALLOWED': 'NO', 'ENABLE_APP_SANDBOX': 'YES', 'SKIP_INSTALL': 'YES',
    'APPLICATION_EXTENSION_API_ONLY': 'YES', 'GENERATE_INFOPLIST_FILE': 'NO',
    'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/../Frameworks', '@executable_path/../../../../Frameworks'],
    'ALWAYS_SEARCH_USER_PATHS': 'NO', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES', 'CURRENT_PROJECT_VERSION': '11', 'MARKETING_VERSION': '1.4.1',
    'SWIFT_OPTIMIZATION_LEVEL': '-O', 'SWIFT_COMPILATION_MODE': 'wholemodule', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
}
configs = [obj('target' + name, 'XCBuildConfiguration', name=name, buildSettings=settings) for name in ['Debug', 'Release']]
config_list = obj('targetconfig', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
target = obj('target', 'PBXNativeTarget', buildConfigurationList=config_list, buildPhases=[sources, frameworks],
             buildRules=[], dependencies=[], name='FluxaWidget', productName='FluxaWidget', productReference=product,
             productType='com.apple.product-type.app-extension')
configs = [obj('project' + name, 'XCBuildConfiguration', name=name, buildSettings={'SDKROOT': 'macosx', 'MACOSX_DEPLOYMENT_TARGET': '14.0'}) for name in ['Debug', 'Release']]
config_list = obj('projectconfig', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
project = obj('project', 'PBXProject', attributes={'LastUpgradeCheck': '2700'}, buildConfigurationList=config_list,
              compatibilityVersion='Xcode 14.0', developmentRegion='en', hasScannedForEncodings=0,
              knownRegions=['en', 'zh-Hans', 'Base'], mainGroup=main, productRefGroup=products,
              projectDirPath='', projectRoot='', targets=[target])
directory = Path(__file__).resolve().parent.parent / 'FluxaWidget.xcodeproj'
directory.mkdir(exist_ok=True)
(directory / 'project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion': '1', 'classes': {}, 'objectVersion': '56', 'objects': objects, 'rootObject': project}, sort_keys=False))
