/*
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatelessWidget {
  final FirestoreService firestore = FirestoreService();
  final messageController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthService>().user!;
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat'),
        actions: [
          IconButton(
            onPressed: () => context.read<AuthService>().logout(),
            icon: Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: firestore.getMessages(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return Center(child: CircularProgressIndicator());
                final messages = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (ctx, index) {
                    final msg = messages[index];
                    return MessageBubble(
                      text: msg['text'],
                      isMe: msg['userId'] == user.uid,
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                      controller: messageController,
                      decoration: InputDecoration(labelText: 'Nachricht...')),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () {
                    firestore.sendMessage(messageController.text, user.uid);
                    messageController.clear();
                  },
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
*/
