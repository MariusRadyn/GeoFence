import 'package:flutter/material.dart';
import 'package:geofence/operatorEditPage.dart';
import 'package:geofence/utils.dart';
import 'package:http/http.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class OperatorsPage extends StatefulWidget {
  const OperatorsPage({super.key});

  @override
  State<OperatorsPage> createState() => _OperatorsPageState();
}

class _OperatorsPageState extends State<OperatorsPage> {
  OperatorData? selectedOperator;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OperatorService>().load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    super.dispose();
  }


  Widget getAvatar(String photoUrl, {double size = 48}) {
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
        // Optional: cache key override if you add versioning manually
      ),
    );
  }
  String buildPhotoUrlWithVersion(String photoUrl, int? version) {
    if (photoUrl.isEmpty) return photoUrl;
    if (version == null) return photoUrl;
    final separator = photoUrl.contains('?') ? '&' : '?';
    return '$photoUrl${separator}v=$version';
  }
  void _addNew() async {
    if (!mounted) return;

    OperatorService operatorService = context.read<OperatorService>();
    final docId = await operatorService.addNew();
  }
  void _deleteOperatorDialog(OperatorData operator) async {
    showDialog(
        context: context,
        builder: (context){
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(
                color: Colors.blue, // Border color
                width: 2, // Border width
              ),
            ),
            backgroundColor: APP_TILE_COLOR,
            shadowColor: Colors.black,
            title: const MyText(
                text: "Delete",
                color: Colors.white
            ),
            content: MyText(
              text: "${operator.name} ${operator.surname}\nAre you sure?",
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
                    _delete(operator);

                    Navigator.pop(context);
                  }
              ),
            ],
          );
        }
    );
  }
  void _delete(OperatorData operator) async {
    if (!mounted) return;

    try{
      OperatorService operatorService = context.read<OperatorService>();
      await operatorService.delete(operator);

    }
    catch (e, st) {
      MyGlobalSnackBar.show('Image Error: $e\n$st');
    }

  }


  @override
  Widget build(BuildContext context) {
    return Consumer<OperatorService>(
      builder: (_, operatorService, __) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: APP_BAR_COLOR,
            foregroundColor: Colors.white,
            title: MyAppbarTitle('Operators'),
          ),
          backgroundColor: APP_BACKGROUND_COLOR,
          floatingActionButton: FloatingActionButton(
            backgroundColor: COLOR_ORANGE,
            foregroundColor: Colors.white,
            onPressed: (){
              _addNew();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OperatorEditPage(
                      operatorData: context.read<OperatorService>().newOperator,
                  ),
                ),
              );
            },
            child: Icon(Icons.add),
          ),
          body: (operatorService.isLoading) ? MyProgressCircle():
            (operatorService.lstOperators.isEmpty) ? MyCenterMsg('No Operators')
            : Column(
            children: [
              SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: operatorService.lstOperators.length,
                    itemBuilder: (context, index){
                      final operator = operatorService.lstOperators[index];
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            child: MyOperatorTile(
                              operator: operator,
                              onTapTile: () async{
                                final image = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => OperatorEditPage(
                                          operatorData: operator
                                      ),
                                  ),
                                );
                                if(image != null){

                                }
                              },
                              onTapDelete: (){
                                _deleteOperatorDialog(operator);
                              },
                            ),
                          )
                        ],
                      );
                    }
                )
              )
            ],
          ),
        );
      },
    );
  }
}

