import 'dart:async';

//import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/app_flavor.dart';
import 'package:geofence/iot_data_summary_page.dart';
//import 'package:geofence/firebase.dart';
import 'package:geofence/contact_us_page.dart';
import 'package:geofence/login_page.dart';
import 'package:geofence/legal_documents_page.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/operators_page.dart';
import 'package:geofence/organisations_page.dart';
import 'package:geofence/org_setup_page.dart';
import 'package:geofence/Tracking_page.dart';
import 'package:geofence/base_station_page.dart';
import 'package:geofence/geo_fence_page.dart';
import 'package:geofence/profile_page.dart';
import 'package:geofence/settings_page.dart';
import 'package:geofence/order_history_page.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/shop_setup_page.dart';
import 'package:geofence/subscriptions_page.dart';
import 'package:geofence/tracking_history_page.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/wages_summary_page.dart';
import 'package:geofence/whats_new_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'iot_monitors_page.dart';

class HomePage extends StatefulWidget {
  final bool openProfileOnLaunch;
  final bool openShopOnLaunch;

  const HomePage({
    super.key,
    this.openProfileOnLaunch = false,
    this.openShopOnLaunch = false,
  });

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controllerDraw;
  late Animation<double> _animationDraw;
  final double drawerWidth = 250;
  Timer? _loadingTimer;
  bool busyLoggingIn = false;
  bool _profileLaunchHandled = false;
  bool _shopLaunchHandled = false;
  bool _orgSetupShown = false;
  String? _profileLoadRequestedForUid;
  String _versionLabel = '';

  final Color colorMenuIcons = Colors.blue;
  final Color colorMenuHeader = Colors.white;
  final Color colorMenuText = Colors.white;

  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwController2 = TextEditingController();
  final TextEditingController _userController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVersionLabel();
    _validateUser();
    orgService.registerRoleChangeHandler(_onRemoteRoleChanged);
    orgService.registerMembershipRemovedHandler(_onRemoteMembershipRemoved);
    _controllerDraw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animationDraw = Tween<double>(
      begin: -drawerWidth,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _controllerDraw,
        curve: Curves.easeInOut,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
    });
  }

  void _onRemoteRoleChanged(String oldRole, String newRole, String orgName) {
    if (!mounted) return;

    // Close drawer and leave restricted screens so menus rebuild for the new role.
    if (_controllerDraw.isCompleted || _controllerDraw.value > 0) {
      _controllerDraw.reverse();
    }
    navigatorKey.currentState?.popUntil((route) => route.isFirst);

    final from = orgRoleLabel(oldRole);
    final to = orgRoleLabel(newRole);
    MyGlobalMessage.show(
      'Role changed',
      'Your role for $orgName changed from $from to $to.\n'
          'Menus and permissions have been updated.',
      MyMessageType.info,
    );
  }

  void _onRemoteMembershipRemoved(
    String removedOrgName,
    String? switchedToOrgName,
  ) {
    if (!mounted) return;

    if (_controllerDraw.isCompleted || _controllerDraw.value > 0) {
      _controllerDraw.reverse();
    }
    navigatorKey.currentState?.popUntil((route) => route.isFirst);

    final switched = (switchedToOrgName ?? '').trim();
    final message = switched.isNotEmpty
        ? 'You were removed from $removedOrgName.\n'
            'Switched back to $switched.'
        : 'You were removed from $removedOrgName.';
    MyGlobalMessage.show(
      'Profile removed',
      message,
      MyMessageType.info,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    orgService.unregisterRoleChangeHandler(_onRemoteRoleChanged);
    orgService.unregisterMembershipRemovedHandler(_onRemoteMembershipRemoved);
    WidgetsBinding.instance.removeObserver(this);
    _userController.dispose();
    _emailController.dispose();
    _pwController.dispose();
    _pwController2.dispose();
    _loadingTimer?.cancel();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final user = context.read<UserDataService>();
    if (user.isLoggingOut || FirebaseAuth.instance.currentUser == null) {
      return;
    }
    user.load();
    context.read<SettingsService>().load();
  }

  Future<void> _loadVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _versionLabel = '${info.version}+${info.buildNumber}';
    });
  }
  void toggleDrawer() {
    if (_controllerDraw.isCompleted) {
      _controllerDraw.reverse();
    } else {
      _controllerDraw.forward();
    }
  }

  bool _isLinkedProfile(OrgService org) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final m = org.membership;
    if (uid == null || m == null) return false;
    // Own profile = orgId/ownerUid is this user; anything else is linked.
    return m.orgId != uid && m.ownerUid != uid;
  }

  String _linkedProfileDescription(OrgService org) {
    final m = org.membership;
    if (m == null) return 'Linked profile';
    return '${m.displayName} · ${orgRoleLabel(m.role)}';
  }

  List<Widget> _buildHomeTiles(OrgService org) {
    final tiles = <Widget>[];
    final canEditFarm = !org.hasOrg || org.canEditFarm;
    final canBilling = !org.hasOrg || org.canManageBilling;
    final isEmployee = org.hasOrg && org.membership?.isEmployee == true;

    void addTile(Widget tile) {
      if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 10));
      tiles.add(tile);
    }

    addTile(
      MyCustomTileWithPic(
        imagePath: iconWhatsNew,
        header: "What's New",
        description: 'Latest updates, features, and improvements',
        widget: const WhatsNewPage(),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WhatsNewPage()),
          );
        },
      ),
    );

    if (AppConfig.showBaseStations && canEditFarm) {
      addTile(
        MyCustomTileWithPic(
          imagePath: iconBase,
          header: 'Base Stations',
          description:
              'Add multiple base stations that acts as master network controllers.',
          widget: BaseStationPage(),
        ),
      );
    }

    if (AppConfig.showIotMonitors && canEditFarm) {
      addTile(
        const MyCustomTileWithPic(
          imagePath: iconIot,
          header: 'iOT Devices',
          description:
              'Add Limitless IOT or third party IOT devices',
          widget: IotMonitorsPage(),
        ),
      );
    }

    if (AppConfig.showOperators && canEditFarm) {
      addTile(
        const MyCustomTileWithPic(
          imagePath: iconOperators,
          header: 'Tags',
          description: 'Manage employee and supervisor tags',
          widget: OperatorsPage(),
        ),
      );
    }

    if (AppConfig.showIotDataReport) {
      addTile(
        const MyCustomTileWithPic(
          imagePath: iconReport,
          header: 'iOT Data Report',
          description: 'View all the iOT data history',
          widget: IotDataPage(),
        ),
      );
    }

    if (AppConfig.addWages && !isEmployee) {
      addTile(
        MyCustomTileWithPic(
          imagePath: iconWages,
          header: 'Wages',
          description: 'View operator wage summaries from IoT distance logs',
          widget: const WagesPage(),
        ),
      );
    }

    if (AppConfig.addShop && canBilling) {
      addTile(
        const MyCustomTileWithPic(
          imagePath: iconShop,
          header: 'Online Shop',
          description: 'Browse Limitless IoT products',
          widget: ShopPage(),
        ),
      );
    }

    return tiles;
  }
  void _openDrawerPage(Widget page) {
    // Close the drawer first, then push — avoids jank from animating both at once.
    if (_controllerDraw.isCompleted || _controllerDraw.value > 0) {
      _controllerDraw.reverse();
    }
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
    });
  }
  List<Widget> _buildDrawerItems(UserDataService user, OrgService org) {
    final items = <Widget>[];

    void open(Widget page) => _openDrawerPage(page);

    ListTile drawerTile({
      required IconData icon,
      required String title,
      required VoidCallback onTap,
    }) {
      return ListTile(
        leading: Icon(icon, color: colorMenuIcons),
        title: Text(title, style: TextStyle(color: colorMenuText)),
        onTap: onTap,
      );
    }

    Widget heading(String text, {bool first = false}) {
      return Padding(
        padding: first
            ? const EdgeInsets.only(top: 10, left: 10)
            : const EdgeInsets.fromLTRB(10, 20, 10, 0),
        child: MyTextHeader(
          text: text,
          color: colorMenuHeader,
          fontsize: 18,
          linecolor: colorAppBackground,
        ),
      );
    }

    final canEditFarm = !org.hasOrg || org.canEditFarm;
    final canBilling = !org.hasOrg || org.canManageBilling;
    final isEmployee = org.hasOrg && org.membership?.isEmployee == true;

    final showTrackingSection = AppConfig.showLiveTracking ||
        AppConfig.showGeoFenceSetup ||
        AppConfig.showTrackingHistory;
    final showIotSection = AppConfig.showBaseStations ||
        AppConfig.showIotMonitors ||
        AppConfig.showIotDataReport;
    final showShopSection = AppConfig.showShop && canBilling;
    final showGeneralSection = true;
    final userIsDeveloper = user.userdata?.isDeveloper == true;
    final showSetupShop = (enableSetupShop || userIsDeveloper) && canBilling;
    final showSetupSection = (AppConfig.showSettings && canEditFarm) ||
        (AppConfig.showOperators && canEditFarm) ||
        showSetupShop ||
        org.hasOrg;

    if (showIotSection) {
      items.add(heading('iOT', first: true));
      if (AppConfig.showBaseStations && canEditFarm) {
        items.add(drawerTile(
          icon: Icons.cell_tower,
          title: 'Base Station',
          onTap: () => open(BaseStationPage()),
        ));
      }
      if (AppConfig.showIotMonitors && canEditFarm) {
        items.add(drawerTile(
          icon: Icons.monitor,
          title: 'iOT Devices',
          onTap: () => open(const IotMonitorsPage()),
        ));
      }
      if (AppConfig.showIotDataReport) {
        items.add(drawerTile(
          icon: Icons.dataset,
          title: 'iOT Data',
          onTap: () => open(const IotDataPage()),
        ));
      }
    }

    if (showShopSection) {
      items.add(heading('Shop', first: !showIotSection));
      items.add(drawerTile(
        icon: Icons.storefront_outlined,
        title: 'Online Shop',
        onTap: () => open(const ShopPage()),
      ));
      items.add(drawerTile(
        icon: Icons.receipt_long_outlined,
        title: 'Order History',
        onTap: () => open(const OrderHistoryPage()),
      ));
      items.add(drawerTile(
        icon: Icons.subscriptions_outlined,
        title: 'Subscriptions',
        onTap: () => open(const SubscriptionsPage()),
      ));
    }

    if (showTrackingSection) {
      items.add(heading(
        'Tracking',
        first: !showIotSection && !showShopSection,
      ));
      if (AppConfig.showLiveTracking) {
        items.add(drawerTile(
          icon: Icons.gps_fixed,
          title: 'Track',
          onTap: () => open(TrackingPage()),
        ));
      }
      if (AppConfig.showGeoFenceSetup && canEditFarm) {
        items.add(drawerTile(
          icon: Icons.fence,
          title: 'GeoFence',
          onTap: () => open(const GeoFencePage()),
        ));
      }
      if (AppConfig.showTrackingHistory) {
        items.add(drawerTile(
          icon: Icons.history,
          title: 'Tracking History',
          onTap: () => open(const TrackingHistoryPage()),
        ));
      }
    }

    if (showGeneralSection) {
      items.add(heading(
        'General',
        first: !showIotSection && !showShopSection && !showTrackingSection,
      ));
      if (AppConfig.showWages && !isEmployee) {
        items.add(drawerTile(
          icon: Icons.attach_money_sharp,
          title: 'Wages',
          onTap: () => open(const WagesPage()),
        ));
      }
      items.add(drawerTile(
        icon: Icons.gavel_outlined,
        title: 'Legal Documents',
        onTap: () => open(const LegalDocumentsPage()),
      ));
    }

    if (showSetupSection) {
      items.add(heading(
        'Setup',
        first: !showIotSection &&
            !showShopSection &&
            !showTrackingSection &&
            !showGeneralSection,
      ));
      if (AppConfig.showSettings && canEditFarm) {
        items.add(drawerTile(
          icon: Icons.settings,
          title: 'Settings',
          onTap: () => open(SettingsPage(userId: user.userdata!.userID)),
        ));
      }
      if (AppConfig.showOperators && canEditFarm) {
        items.add(drawerTile(
          icon: Icons.person,
          title: 'Tags',
          onTap: () => open(const OperatorsPage()),
        ));
      }
      if (org.hasOrg) {
        items.add(drawerTile(
          icon: Icons.business_outlined,
          title: 'Link Profile',
          onTap: () => open(const OrganisationsPage()),
        ));
      }
      if (showSetupShop) {
        items.add(drawerTile(
          icon: Icons.store_mall_directory_outlined,
          title: 'Setup Shop',
          onTap: () => open(const ShopSetupPage()),
        ));
      }
    }

    items.add(drawerTile(
      icon: Icons.lightbulb_outline,
      title: 'Contact Us',
      onTap: () => open(const ContactUsPage()),
    ));

    items.add(const SizedBox(height: 5));
    return items;
  }
  Future<void> _ensureOrgSetup({
    required UserDataService user,
    required OrgService org,
  }) async {
    if (_orgSetupShown) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    if (user.userdata == null) return;
    if (user.userdata?.emailValidated != true) return;
    if (org.isLoading) return;

    // Profile exists but org membership not resolved yet — refresh once.
    if (!org.hasOrg && !org.needsSetup) {
      await org.refreshAfterProfileReady();
      if (!mounted) return;
    }

    if (!org.needsSetup || org.hasOrg) return;

    _orgSetupShown = true;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OrgSetupPage()),
    );
    if (!mounted) return;
    _orgSetupShown = false;
    await org.load();
  }

  Future<void> _openShopOnLaunch() async {
    if (!AppConfig.addShop) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ShopPage()),
    );
  }

  Future<void> _openProfileOnLaunch() async {
    final userService = context.read<UserDataService>();
    await userService.load();

    if (!mounted) return;

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
    );
  }
  Future<void> _login({
    required UserDataService user,
  }) async {
    // Prefer live auth/profile state — tap-time flags go stale during await.
    if (FirebaseAuth.instance.currentUser != null && user.userdata == null) {
      await user.load();
    }
    if (!mounted) return;

    final fullyLoggedIn =
        FirebaseAuth.instance.currentUser != null && user.userdata != null;

    if (fullyLoggedIn) {
      if (user.userdata?.emailValidated != true) {
        MyGlobalMessage.show(
          'Verify Email',
          'Please open your email.\nClick on the verify link',
          MyMessageType.info,
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      );
      return;
    }

    // Not signed in (or profile missing) — always open credentials.
    if (busyLoggingIn) {
      setState(() => busyLoggingIn = false);
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
    );
    if (!mounted) return;
    await user.load();
  }
  Future<void> _validateUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      await user.reload();   // Forces server check
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        await FirebaseAuth.instance.signOut();
      }
    }
  }
  void _startTimeout(int sec) {
    // Already armed — don't restart on every rebuild.
    if (_loadingTimer != null) return;

    _loadingTimer = Timer(Duration(seconds: sec), () {
      if (!mounted) return;
      // Never sign out on a load timeout — that forced re-login on web.
      setState(() {
        busyLoggingIn = false;
      });
      MyGlobalMessage.show(
        "Timeout",
        "Loading took too long. Try again.",
        MyMessageType.warning,
      );
    });
  }
  void _cancelLoadingTimeout() {
    _loadingTimer?.cancel();
    _loadingTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return
      StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {

          return Consumer3<SettingsService, UserDataService, OrgService>(
              builder: (context, settings, user, org, __) {
                final authWaiting =
                    snapshot.connectionState == ConnectionState.waiting;
                final authUser = snapshot.data;
                final profilePending =
                    authUser != null && user.userdata == null;
                // Only block UI while a load is actually in progress — not when
                // auth exists but Firestore profile is missing/failed (that used
                // to leave the spinner up until the 10s timeout).
                final profileSyncing =
                    profilePending && (user.isLoading || settings.isLoading);
                final userLoggedIn =
                    authUser != null && user.userdata != null;
                final orgPending = userLoggedIn &&
                    user.userdata?.emailValidated == true &&
                    (org.isLoading || (!org.isReady));
                final showLoadingOverlay =
                    authWaiting || busyLoggingIn || profileSyncing || orgPending;

                String image = "";
                if (user.userdata != null) {
                  image = user.userdata!.imageURL ?? "";
                }

                if (showLoadingOverlay) {
                  _startTimeout(20);
                } else {
                  _cancelLoadingTimeout();
                }

                if (authUser == null) {
                  _profileLoadRequestedForUid = null;
                  _orgSetupShown = false;
                  if (busyLoggingIn) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => busyLoggingIn = false);
                    });
                  }
                  _cancelLoadingTimeout();
                } else if (!user.isLoggingOut &&
                    user.userdata == null &&
                    !user.isLoading &&
                    _profileLoadRequestedForUid != authUser.uid) {
                  _profileLoadRequestedForUid = authUser.uid;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (user.isLoggingOut ||
                        FirebaseAuth.instance.currentUser == null) {
                      return;
                    }
                    user.load();
                    settings.load();
                    org.refreshAfterProfileReady();
                  });
                }

                if (userLoggedIn &&
                    user.userdata?.emailValidated == true &&
                    !orgPending &&
                    !profileSyncing) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _ensureOrgSetup(user: user, org: org);
                  });
                }

                if (widget.openProfileOnLaunch && !_profileLaunchHandled) {
                  _profileLaunchHandled = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _openProfileOnLaunch();
                  });
                }

                if (widget.openShopOnLaunch && !_shopLaunchHandled) {
                  _shopLaunchHandled = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _openShopOnLaunch();
                  });
                }

                return Scaffold(

                  backgroundColor: const Color(0xFF020617),
                  body: homeBackground(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: Column(
                              children: [
                                AppBar(
                                  iconTheme: IconThemeData(color: colorIceBlue),
                                  backgroundColor: Colors.transparent,
                                  elevation: 0,
                                  scrolledUnderElevation: 0,
                                  toolbarHeight: _isLinkedProfile(org) ? 72 : kToolbarHeight,
                                  leading: GestureDetector(
                                    onTap: () {
                                      if (userLoggedIn) toggleDrawer();
                                    },
                                    child: Icon(Icons.menu),
                                  ),
                                  title: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      myAppbarTitle("Limitless iOT"),
                                      if (_isLinkedProfile(org))
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 1),
                                          child: Text(
                                            _linkedProfileDescription(org),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white.withValues(alpha: 0.75),
                                            ),
                                          ),
                                        ),
                                      myConnectionStatus(settings: settings),
                                    ],
                                  ),
                                  actions: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [

                                        // Profile Pic
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              right: 10, top: 2, bottom: 2),
                                          child: GestureDetector(
                                            onTap: () async {
                                              await _login(
                                                user: user,
                                              );
                                            },
                                
                                            // Profile Pic
                                            child: Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: Colors.white,
                                                    width: 0.5),
                                                // Clean white border
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.1),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: NetworkCircleAvatar(
                                                imageUrl: userLoggedIn ? image : null,
                                                radius: 18,
                                                backgroundColor: colorIceBlue,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                
                                !userLoggedIn
                                  ? Expanded(
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          GestureDetector(
                                            onTap: ()async{
                                              await _login(
                                                user: user,
                                              );
                                            },
                                            child: MyText(text: "Please  Log in")
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  :
                                // =========================
                                // Page Data
                                // =========================
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 20),

                                        ..._buildHomeTiles(org),

                                        const SizedBox(height: 15),
                                      ],
                                    ),
                                  ),
                                ),
                                
                              ]),
                        ),

                        if (userLoggedIn)
                          AnimatedBuilder(
                              animation: _animationDraw,
                              builder: (context, child) {
                                bool isDrawerVisible = _animationDraw.value > -drawerWidth;
                                return Stack(
                                  children: [

                                    // =========================
                                    // Scrim (Tap to close)
                                    // =========================
                                    if(isDrawerVisible)
                                      Positioned.fill(
                                        child: GestureDetector(
                                          onTap: () => toggleDrawer(),
                                          // Closes the drawer when background is tapped
                                          behavior: HitTestBehavior.opaque,
                                          child: Container(
                                            color: Colors.black.withValues(
                                                alpha: 0.5), // Dim the background slightly
                                          ),
                                        ),
                                      ),

                                    // =========================
                                    // Menu Drawer
                                    // =========================

                                    Positioned(
                                        left: _animationDraw.value,
                                        top: 35,
                                        bottom: 15,
                                        child: Container(
                                          width: drawerWidth,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.only(
                                                topRight: Radius.circular(20),
                                                bottomRight: Radius.circular(20)
                                            ),
                                            color: colorTile,
                                          ),

                                          // Menu
                                          child: Column(
                                              children: [

                                                // Menu Header
                                                Container(
                                                  height: 120,
                                                  width: drawerWidth,
                                                  decoration: BoxDecoration(
                                                    gradient: myTileGradient(),
                                                    borderRadius: BorderRadius.only(topRight: Radius.circular(20),
                                                    ),
                                                  ),

                                                  // Menu Header
                                                  child: Column(
                                                    children: [

                                                      /// TOP ROW
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment
                                                            .spaceBetween,
                                                        crossAxisAlignment: CrossAxisAlignment
                                                            .center,
                                                        children: [
                                                          Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 5),
                                                            child: myAppbarTitle("Menu"),
                                                          ),

                                                          Image.asset(
                                                            iconLimitlessLogo,
                                                            width: 50,
                                                            height: 40,
                                                            fit: BoxFit.contain,
                                                          ),
                                                        ],
                                                      ),

                                                      Spacer(),

                                                      /// BOTTOM INFO
                                                      Row(
                                                        crossAxisAlignment: CrossAxisAlignment
                                                            .start,
                                                        children: [
                                                          Column(
                                                            crossAxisAlignment: CrossAxisAlignment
                                                                .start,
                                                            children: [
                                                              Padding(
                                                                padding: const EdgeInsets.symmetric(horizontal: 5.0),
                                                                child: MyText(
                                                                  text: _versionLabel.isNotEmpty
                                                                      ? _versionLabel
                                                                      : APP_VERSION,
                                                                  color: Colors
                                                                      .grey,
                                                                ),
                                                              ),
                                                              Padding(
                                                                padding: const EdgeInsets.symmetric(horizontal: 5.0),
                                                                child: MyText(
                                                                  text: user
                                                                      .userdata!.displayName,
                                                                  color: Colors
                                                                      .grey,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),

                                                      SizedBox(height: 10,)
                                                    ],
                                                  ),
                                                ),

                                                // Menu
                                                Expanded(
                                                  child: Material(
                                                    type: MaterialType.transparency,
                                                    color: colorTile,
                                                    child: ListTileTheme(
                                                      data: ListTileThemeData(
                                                        tileColor: colorTile,
                                                        selectedTileColor: colorTile,
                                                      ),
                                                      child: ListView(
                                                        padding: EdgeInsets.zero,
                                                        children:
                                                            _buildDrawerItems(user, org),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ]
                                          ),
                                        )
                                    ),
                                  ],
                                );
                              }
                          ),
                        if (showLoadingOverlay)
                          Positioned.fill(
                            child: ColoredBox(
                              color: const Color(0xFF020617).withValues(alpha: 0.92),
                              child: Center(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 32),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 32,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorAppTitle,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      myProgressCircle(),
                                      if (profilePending) ...[
                                        const SizedBox(height: 16),
                                        const MyText(
                                          text: "Logging in...",
                                          color: Colors.white,
                                          fontsize: 16,
                                        ),
                                        const SizedBox(height: 8),
                                        const MyText(
                                          text:
                                              "Please wait while we set up your account.",
                                          color: Colors.grey,
                                          fontsize: 13,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }
          );    // Not logged in
        },
      );
  }
}
