require "spec_helper"

describe Gitlab::Email::Receiver, lib: true do
  before do
    stub_incoming_email_setting(enabled: true, address: "reply+%{key}@appmail.adventuretime.ooo")
  end

  let(:reply_key) { "59d8df8370b7e95c5a49fbf86aeb2c93" }
  let(:email_raw) { fixture_file('emails/valid_reply.eml') }

  let(:project)   { create(:project, :public) }
  let(:noteable)  { create(:issue, project: project) }
  let(:user)      { create(:user) }
  let!(:sent_notification) { SentNotification.record(noteable, user.id, reply_key) }

  let(:receiver) { described_class.new(email_raw) }

  context "when the recipient address doesn't include a reply key" do
    let(:email_raw) { fixture_file('emails/valid_reply.eml').gsub(reply_key, "") }

    it "raises a SentNotificationNotFoundError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::SentNotificationNotFoundError)
    end
  end

  context "when no sent notificiation for the reply key could be found" do
    let(:email_raw) { fixture_file('emails/wrong_reply_key.eml') }

    it "raises a SentNotificationNotFoundError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::SentNotificationNotFoundError)
    end
  end

  context "when the email is blank" do
    let(:email_raw) { "" }

    it "raises an EmptyEmailError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::EmptyEmailError)
    end
  end

  context "when the email was auto generated" do
    let!(:reply_key) { '636ca428858779856c226bb145ef4fad' }
    let!(:email_raw) { fixture_file("emails/auto_reply.eml") }
    
    it "raises an AutoGeneratedEmailError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::AutoGeneratedEmailError)
    end
  end

  context "when the user could not be found" do
    before do
      user.destroy
    end

    it "raises a UserNotFoundError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::UserNotFoundError)
    end
  end

  context "when the user has been blocked" do
    before do
      user.block
    end

    it "raises a UserBlockedError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::UserBlockedError)
    end
  end

  context "when the user is not authorized to create a note" do
    before do
      project.update_attribute(:visibility_level, Project::PRIVATE)
    end

    it "raises a UserNotAuthorizedError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::UserNotAuthorizedError)
    end
  end

  context "when the noteable could not be found" do
    before do
      noteable.destroy
    end

    it "raises a NoteableNotFoundError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::NoteableNotFoundError)
    end
  end

  context "when the reply is blank" do
    let!(:email_raw) { fixture_file("emails/no_content_reply.eml") }
    
    it "raises an EmptyEmailError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::EmptyEmailError)
    end
  end

  context "when the note could not be saved" do
    before do
      allow_any_instance_of(Note).to receive(:persisted?).and_return(false)
    end

    it "raises an InvalidNoteError" do
      expect { receiver.execute }.to raise_error(Gitlab::Email::Receiver::InvalidNoteError)
    end
  end

  context "when everything is fine" do
    before do
      allow_any_instance_of(Gitlab::Email::AttachmentUploader).to receive(:execute).and_return(
        [
          {
            url: "uploads/image.png",
            is_image: true,
            alt: "image"
          }
        ]
      )
    end

    it "creates a comment" do
      expect { receiver.execute }.to change { noteable.notes.count }.by(1)
      note = noteable.notes.last

      expect(note.author).to eq(sent_notification.recipient)
      expect(note.note).to include("I could not disagree more.")
    end

    it "adds all attachments" do
      receiver.execute

      note = noteable.notes.last

      expect(note.note).to include("![image](uploads/image.png)")
    end
  end
end
