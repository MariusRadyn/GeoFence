import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/operator_edit_page.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class OperatorsPage extends StatefulWidget {
  const OperatorsPage({super.key});

  @override
  State<OperatorsPage> createState() => OperatorsPageState();
}

class OperatorsPageState extends State<OperatorsPage>
    with SingleTickerProviderStateMixin {
  OperatorData? selectedOperator;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OperatorService>().load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget getAvatar(String photoUrl, {double size = 48}) {
    if (photoUrl.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.asset(
          iconProfile,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: NetworkAvatar(imageUrl: photoUrl, size: size),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: CachedNetworkImage(
        imageUrl: photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: size,
          height: size,
          color: const Color(0xFFE0E0E0),
        ),
        errorWidget: (context, url, error) => Container(
          width: size,
          height: size,
          color: const Color(0xFFEEEEEE),
          child: const Icon(Icons.person_outline),
        ),
      ),
    );
  }

  String buildPhotoUrlWithVersion(String photoUrl, int? version) {
    if (photoUrl.isEmpty) return photoUrl;
    if (version == null) return photoUrl;
    final separator = photoUrl.contains('?') ? '&' : '?';
    return '$photoUrl${separator}v=$version';
  }

  Future<OperatorData?> _addNew() async {
    if (!mounted) return null;

    final accessLevel = _tabController.index == 1
        ? operatorTypeSupervisor
        : operatorTypeEmployee;
    final operatorService = context.read<OperatorService>();
    return operatorService.addNew(accessLevel: accessLevel);
  }

  void _deleteOperatorDialog(OperatorData operator) async {
    final operatorService = context.read<OperatorService>();
    final hasWageLinks = await operatorService.hasLinkedWageRecords(operator.docId);

    if (!mounted) return;

    final message = hasWageLinks
        ? '${operator.name} ${operator.surname} has wage records linked.\n\n'
            'They will be hidden from the tags list, but past records '
            'will still show their name.\n\nContinue?'
        : '${operator.name} ${operator.surname}\nAre you sure?';

    showDialog(
        context: context,
        builder: (context){
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(
                color: Colors.blue,
                width: 2,
              ),
            ),
            backgroundColor: colorAppTitle,
            shadowColor: Colors.black,
            title: MyText(
                text: hasWageLinks ? "Warning" : "Delete",
                color: Colors.white
            ),
            content: MyText(
              text: message,
              color: Colors.grey,
              fontsize: 18,
            ),
            actions: [
              TextButton(
                child: const MyText(
                  text: 'No',
                  fontsize: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                  child: const MyText(
                    text: 'Yes',
                    color:  Colors.white,
                    fontsize: 20,
                  ),

                  onPressed: () async {
                    Navigator.pop(context);
                    await _delete(operator, hasWageLinks: hasWageLinks);
                  }
              ),
            ],
          );
        }
    );
  }

  Future<void> _delete(
    OperatorData operator, {
    required bool hasWageLinks,
  }) async {
    if (!mounted) return;

    try{
      OperatorService operatorService = context.read<OperatorService>();
      if (hasWageLinks) {
        await operatorService.markForDelete(operator);
      } else {
        await operatorService.delete(operator);
      }
    }
    catch (e, st) {
      MyGlobalSnackBar.show('Delete Error: $e\n$st');
    }
  }

  List<OperatorData> _employees(List<OperatorData> all) =>
      all.where((o) => isEmployeeAccessLevel(o.accessLevel)).toList();

  List<OperatorData> _supervisors(List<OperatorData> all) =>
      all.where((o) => isSupervisorAccessLevel(o.accessLevel)).toList();

  Widget _buildTagList(List<OperatorData> operators, String emptyMessage) {
    if (operators.isEmpty) {
      return myCenterMsg(emptyMessage);
    }

    return ListView.builder(
      itemCount: operators.length,
      itemBuilder: (context, index) {
        final operator = operators[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: MyOperatorTile(
            key: ValueKey(
              '${operator.docId}_${operator.imageFilename}_${operator.imageURL}',
            ),
            operator: operator,
            onTapTile: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OperatorEditPage(
                    operatorData: operator,
                  ),
                ),
              );
              if (mounted) {
                context.read<OperatorService>().notifyListChanged();
              }
            },
            onTapDelete: () {
              _deleteOperatorDialog(operator);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OperatorService>(
      builder: (_, operatorService, __) {
        final employees = _employees(operatorService.lstOperators);
        final supervisors = _supervisors(operatorService.lstOperators);

        return Scaffold(
          appBar: AppBar(
            backgroundColor: colorAppBar,
            foregroundColor: Colors.white,
            title: myAppbarTitle('Tags'),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: colorOrange,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Employee'),
                Tab(text: 'Supervisor'),
              ],
            ),
          ),
          backgroundColor: colorAppBackground,
          floatingActionButton: FloatingActionButton(
            backgroundColor: colorOrange,
            foregroundColor: Colors.white,
            onPressed: () async {
              OperatorData? newOperator = await _addNew();
              if (newOperator == null) return;
              if (!mounted) return;

              Navigator.push(
                // ignore: use_build_context_synchronously
                context,
                MaterialPageRoute(
                  builder: (context) => OperatorEditPage(
                    operatorData: newOperator,
                  ),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),
          body: operatorService.isLoading
              ? myProgressCircle()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTagList(employees, 'No Employees'),
                    _buildTagList(supervisors, 'No Supervisors'),
                  ],
                ),
        );
      },
    );
  }
}
